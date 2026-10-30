import Foundation

// One method per endpoint of the API contract (apps/api).

extension APIClient {
    // MARK: Operations

    /// `POST /v1/ops`: idempotent by `opId`. `invites` (game → current invite code) lets the
    /// server seat this phone at a table it seated itself at over the link.
    func uploadOperations(_ operations: [GameOperation], invites: [GameID: String] = [:]) async throws -> OpsUploadResult {
        let keyed = Dictionary(invites.map { ($0.key.uuidString.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        return try await send("POST", "v1/ops", body: OpsUpload(ops: operations, invites: keyed.isEmpty ? nil : keyed))
    }

    /// `PUT /v1/games/:gameId/invite-key`: registers the table's invite-code key (first key wins;
    /// 409 when another key is on record, 403 when this account isn't seated there yet).
    func registerInviteKey(_ key: Data, for game: GameID) async throws {
        let _: OKResponse = try await send("PUT", "v1/games/\(game.uuidString.lowercased())/invite-key", body: InviteKeyRequest(key: key.base64URLEncoded))
    }

    /// `GET /v1/players/me/games`: every game this account is seated in, claimed guest seats
    /// included, so a new phone (or a claim) can pull the history it never saw.
    func myGames() async throws -> MyGamesResponse {
        try await send("GET", "v1/players/me/games")
    }

    /// The server's page size for `GET /v1/games/:gameId/ops` (apps/api `DEFAULT_OPS_PAGE`).
    static let opsPageSize = 2000

    /// `GET /v1/games/:gameId/ops?after=<hlcString>`: one page in fold order, starting at the
    /// beginning when `after` is nil. A full page (`opsPageSize`) means ask again after its last op.
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

    /// `GET /v1/players/:playerId/profile`: the server's rating, global rank and lifetime stats.
    func playerProfile(_ player: PlayerID) async throws -> PlayerProfileResponse {
        try await send("GET", "v1/players/\(player.uuidString.lowercased())/profile")
    }

    /// `GET /v1/leaderboard?scope=&sort=`: the server's board over every finished game.
    func leaderboard(scope: String = "global", sort: String = "rating", limit: Int = 100) async throws -> LeaderboardResponse {
        try await send("GET", "v1/leaderboard", query: [
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    /// `PUT /v1/players/me/photo`: uploads a JPEG profile photo; the answer is the https avatar.
    func uploadPhoto(_ jpeg: Data) async throws -> Avatar {
        let response: PhotoUploadResponse = try await sendRaw("PUT", "v1/players/me/photo", body: jpeg, contentType: "image/jpeg")
        return response.avatar
    }

    // MARK: Table link identity

    /// `POST /v1/link/attestations`: the server vouches that this account owns `publicKey`.
    func linkAttestation(device: DeviceID, publicKey: Data) async throws -> LinkAttestationResponse {
        try await send("POST", "v1/link/attestations", body: LinkAttestationRequest(deviceId: device, publicKey: publicKey.base64URLEncoded))
    }

    /// `GET /link/key` (no auth): the key hubs check attestations against.
    func linkKey() async throws -> Data? {
        let response: LinkKeyResponse = try await send("GET", "link/key", authenticated: false)
        return Data(base64URLEncoded: response.publicKey)
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
        let _: OKResponse = try await send("POST", "v1/blocks", body: BlockPlayerBody(playerId: player))
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

    // MARK: Live Activity

    /// `GET /v1/games/:gameId/live-activity`: the APNs broadcast channel the server updates this
    /// game's Live Activity on. nil until the server has created one.
    func liveActivityChannel(for game: GameID) async throws -> String? {
        let response: LiveActivityChannelResponse = try await send("GET", "v1/games/\(game.uuidString.lowercased())/live-activity")
        return response.channelId
    }
}
