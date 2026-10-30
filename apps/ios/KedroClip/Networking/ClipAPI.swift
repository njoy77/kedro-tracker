import Foundation

/// The App Clip's HTTP client. The clip uses the internet only (design §5.8): no peer-to-peer link
/// and no Supabase SDK, so it authenticates with a short-lived, game-scoped token exchanged for the
/// invite link's table token.
///
/// Endpoints (shared contract with `apps/api`):
/// - `POST /v1/clip/sessions {gameId, tableToken, deviceId}` → `{accessToken, expiresAt}`
///   (clip-only addition; the bearer token is accepted by the two game endpoints below for that game)
/// - `GET  /v1/games/:gameId/ops?after=<hlcString>` → `{ops:[Operation]}`
/// - `POST /v1/ops {ops:[Operation]}` → `{accepted:[opId], duplicates:[opId]}`
/// - `POST /v1/clip/claims {gameId, seatId}` → `{claimToken}` (clip-only addition: the token the
///   full app later redeems with `POST /v1/claims`)
nonisolated struct ClipAPI: Sendable {
    enum ClipAPIError: Error, Equatable {
        case badStatus(Int)
        /// No session token yet (call `startSession` first).
        case notConnected
    }

    struct SessionResponse: Codable, Sendable {
        var accessToken: String
        var expiresAt: Date?
    }

    struct OperationsResponse: Codable, Sendable {
        var ops: [GameOperation]
    }

    struct SendResponse: Codable, Sendable {
        var accepted: [UUID]
        var duplicates: [UUID]
    }

    struct ClaimResponse: Codable, Sendable {
        var claimToken: String
    }

    let baseURL: URL
    var session: URLSession = .shared

    /// From the clip's Info.plist (`KedroAPIBaseURL`).
    static func fromBundle() -> ClipAPI? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "KedroAPIBaseURL") as? String,
              let url = URL(string: value), url.host() != nil
        else { return nil }
        return ClipAPI(baseURL: url)
    }

    func startSession(gameID: GameID, tableToken: String, deviceID: DeviceID) async throws -> SessionResponse {
        struct Body: Encodable {
            var gameId: GameID
            var tableToken: String
            var deviceId: DeviceID
        }
        return try await request("POST", "v1/clip/sessions", body: Body(gameId: gameID, tableToken: tableToken, deviceId: deviceID), token: nil)
    }

    func operations(gameID: GameID, after: HLC?, token: String) async throws -> [GameOperation] {
        var path = "v1/games/\(gameID.uuidString)/ops"
        if let after {
            let value = after.stringValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? after.stringValue
            path += "?after=\(value)"
        }
        let response: OperationsResponse = try await request("GET", path, body: Optional<String>.none, token: token)
        return response.ops
    }

    func send(_ operations: [GameOperation], token: String) async throws -> SendResponse {
        struct Body: Encodable { var ops: [GameOperation] }
        return try await request("POST", "v1/ops", body: Body(ops: operations), token: token)
    }

    func claimSeat(gameID: GameID, seatID: SeatID, token: String) async throws -> String {
        struct Body: Encodable {
            var gameId: GameID
            var seatId: SeatID
        }
        let response: ClaimResponse = try await request("POST", "v1/clip/claims", body: Body(gameId: gameID, seatId: seatID), token: token)
        return response.claimToken
    }

    private func request<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body?, token: String?) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw ClipAPIError.badStatus(-1) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try KedroJSON.encoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ClipAPIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try KedroJSON.decoder().decode(Response.self, from: data)
    }
}
