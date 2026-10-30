import Foundation

/// What a reported thing is (`POST /v1/reports` `targetType`).
nonisolated enum ReportTargetType: String, Hashable, Sendable, Codable {
    case taunt, player, photo
}

/// Why something was reported. Literal labels.
nonisolated enum ReportReason: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case slur, abuse, spam, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slur: "It's a slur"
        case .abuse: "It's abuse, not banter"
        case .spam: "It's spam"
        case .other: "Something else"
        }
    }
}

/// `POST /v1/taunts/check` response.
nonisolated struct TauntCheckResponse: Hashable, Sendable, Codable {
    var allowed: Bool
    var reason: String?
}

/// The trash talk endpoints of the API contract: the server taunt check, reports, blocks and
/// receipts. `TrashTalkHTTPClient` is the real one; tests and previews use their own.
nonisolated protocol TrashTalkAPI: Sendable {
    /// `POST /v1/taunts/check {text}` → `{allowed, reason?}`
    func checkTaunt(_ text: String) async throws -> TauntCheckResponse
    /// `POST /v1/reports {targetType, targetId, reason}` → `{ok}`
    func report(_ targetType: ReportTargetType, targetID: String, reason: ReportReason) async throws
    /// `POST /v1/blocks {playerId}` → `{ok}`
    func block(_ player: PlayerID) async throws
    /// `DELETE /v1/blocks/:playerId` → `{ok}`
    func unblock(_ player: PlayerID) async throws
    /// `POST /v1/receipts {gameId, toPlayerId, receiptKey}` → `{ok}`
    func sendReceipt(gameID: GameID, to player: PlayerID, receiptKey: String) async throws
}

nonisolated enum TrashTalkAPIError: Error, Equatable {
    /// No signed-in session (guests can't report or block on the server).
    case notSignedIn
    case badStatus(Int)
    case notOK
}

/// The contract over HTTP: JSON, Supabase JWT bearer auth (`apps/api`).
///
/// TODO(networking): if `Core/Networking/APIClient` grows these endpoints, make it conform to
/// `TrashTalkAPI` and drop this client so there's one HTTP stack.
nonisolated struct TrashTalkHTTPClient: TrashTalkAPI {
    let baseURL: URL
    /// The signed-in user's access token, or nil (guest, signed out).
    let accessToken: @Sendable () async -> String?
    var session: URLSession = .shared
    /// The taunt check runs while someone waits on Send, so it gives up quickly (the on-device
    /// filter has already passed by then).
    var checkTimeout: TimeInterval = 4

    func checkTaunt(_ text: String) async throws -> TauntCheckResponse {
        try await post("v1/taunts/check", body: ["text": text], timeout: checkTimeout)
    }

    func report(_ targetType: ReportTargetType, targetID: String, reason: ReportReason) async throws {
        let response: OKResponse = try await post("v1/reports", body: [
            "targetType": targetType.rawValue, "targetId": targetID, "reason": reason.rawValue,
        ])
        guard response.ok else { throw TrashTalkAPIError.notOK }
    }

    func block(_ player: PlayerID) async throws {
        let response: OKResponse = try await post("v1/blocks", body: ["playerId": player.uuidString.lowercased()])
        guard response.ok else { throw TrashTalkAPIError.notOK }
    }

    func unblock(_ player: PlayerID) async throws {
        var request = try await authorizedRequest("v1/blocks/\(player.uuidString.lowercased())")
        request.httpMethod = "DELETE"
        let response: OKResponse = try await perform(request)
        guard response.ok else { throw TrashTalkAPIError.notOK }
    }

    func sendReceipt(gameID: GameID, to player: PlayerID, receiptKey: String) async throws {
        let response: OKResponse = try await post("v1/receipts", body: [
            "gameId": gameID.uuidString.lowercased(), "toPlayerId": player.uuidString.lowercased(), "receiptKey": receiptKey,
        ])
        guard response.ok else { throw TrashTalkAPIError.notOK }
    }

    // MARK: Private

    private struct OKResponse: Decodable {
        var ok: Bool
    }

    private func post<Response: Decodable>(_ path: String, body: [String: String], timeout: TimeInterval = 15) async throws -> Response {
        var request = try await authorizedRequest(path)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func authorizedRequest(_ path: String) async throws -> URLRequest {
        guard let token = await accessToken() else { throw TrashTalkAPIError.notSignedIn }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw TrashTalkAPIError.badStatus(status) }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

/// No server: the check passes (the on-device filter still runs), everything else fails as if
/// offline, so reports and blocks stay queued. For previews and guest-only phones.
nonisolated struct OfflineTrashTalkAPI: TrashTalkAPI {
    func checkTaunt(_ text: String) async throws -> TauntCheckResponse { throw TrashTalkAPIError.notSignedIn }
    func report(_ targetType: ReportTargetType, targetID: String, reason: ReportReason) async throws { throw TrashTalkAPIError.notSignedIn }
    func block(_ player: PlayerID) async throws { throw TrashTalkAPIError.notSignedIn }
    func unblock(_ player: PlayerID) async throws { throw TrashTalkAPIError.notSignedIn }
    func sendReceipt(gameID: GameID, to player: PlayerID, receiptKey: String) async throws { throw TrashTalkAPIError.notSignedIn }
}
