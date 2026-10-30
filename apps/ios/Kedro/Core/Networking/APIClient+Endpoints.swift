import Foundation

// One method per endpoint of the API contract (apps/api).

extension APIClient {
    // MARK: Operations

    /// `POST /v1/ops`: idempotent by `opId`.
    func uploadOperations(_ operations: [GameOperation]) async throws -> OpsUploadResult {
        try await send("POST", "v1/ops", body: OpsUpload(ops: operations))
    }

    /// `GET /v1/games/:gameId/ops?after=<hlcString>`. nil `after` returns the whole log.
    func operations(for game: GameID, after: HLC? = nil) async throws -> [GameOperation] {
        let query = after.map { [URLQueryItem(name: "after", value: $0.stringValue)] } ?? []
        let page: OpsPage = try await send("GET", "v1/games/\(game.uuidString)/ops", query: query)
        return page.ops
    }

    // MARK: Players

    /// `GET /v1/players/me`.
    func me() async throws -> Player {
        try await send("GET", "v1/players/me")
    }

    /// `PUT /v1/players/me`. The handle must be unique (the server answers 409 when taken).
    func updateMe(_ update: PlayerUpdate) async throws -> Player {
        try await send("PUT", "v1/players/me", body: update)
    }

    /// `GET /v1/players/search?q=`: display name or @handle; blocked players excluded.
    func searchPlayers(_ query: String) async throws -> [PlayerSummary] {
        let result: PlayerSearchResult = try await send("GET", "v1/players/search", query: [URLQueryItem(name: "q", value: query)])
        return result.players
    }

    // MARK: Claims, moderation, receipts

    /// `POST /v1/claims`: moves a guest's history onto the signed-in account.
    func claim(token: String) async throws -> ClaimResult {
        try await send("POST", "v1/claims", body: ClaimRequest(claimToken: token))
    }

    /// `POST /v1/taunts/check`: the server half of the custom taunt filter.
    func checkTaunt(_ text: String) async throws -> TauntCheckResult {
        try await send("POST", "v1/taunts/check", body: TauntCheckRequest(text: text))
    }

    /// `POST /v1/reports`.
    func report(_ request: ReportRequest) async throws {
        let _: OKResponse = try await send("POST", "v1/reports", body: request)
    }

    /// `POST /v1/blocks`.
    func block(_ player: PlayerID) async throws {
        let _: OKResponse = try await send("POST", "v1/blocks", body: BlockRequest(playerId: player))
    }

    /// `DELETE /v1/blocks/:playerId`.
    func unblock(_ player: PlayerID) async throws {
        let _: OKResponse = try await send("DELETE", "v1/blocks/\(player.uuidString)")
    }

    /// `POST /v1/receipts`.
    func sendReceipt(_ request: ReceiptRequest) async throws {
        let _: OKResponse = try await send("POST", "v1/receipts", body: request)
    }

    // MARK: Push

    /// `POST /v1/push/tokens`.
    func registerPushToken(_ request: PushTokenRequest) async throws {
        let _: OKResponse = try await send("POST", "v1/push/tokens", body: request)
    }
}
