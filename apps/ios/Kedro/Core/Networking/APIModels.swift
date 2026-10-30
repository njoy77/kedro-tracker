import Foundation

// Request and response shapes of the Kedro API contract. Field names are the JSON keys.

/// `POST /v1/ops` body.
nonisolated struct OpsUpload: Encodable, Sendable {
    var ops: [GameOperation]
}

/// `POST /v1/ops` response. Idempotent by `opId`: ops already stored come back as duplicates.
/// An op in neither list was refused by the server.
nonisolated struct OpsUploadResult: Codable, Hashable, Sendable {
    var accepted: [UUID]
    var duplicates: [UUID]

    /// Every op the server now holds (accepted now or earlier).
    var stored: Set<UUID> { Set(accepted).union(duplicates) }
}

/// `GET /v1/games/:gameId/ops` response.
nonisolated struct OpsPage: Codable, Sendable {
    var ops: [GameOperation]
}

/// `PUT /v1/players/me` body.
nonisolated struct PlayerUpdate: Codable, Hashable, Sendable {
    var displayName: String
    var handle: Handle
    var avatar: Avatar
}

/// `GET /v1/players/search` response.
nonisolated struct PlayerSearchResult: Codable, Sendable {
    var players: [PlayerSummary]
}

/// `POST /v1/claims` body and response.
nonisolated struct ClaimRequest: Codable, Sendable {
    var claimToken: String
}

nonisolated struct ClaimResult: Codable, Hashable, Sendable {
    var guestId: GuestID
    var gamesClaimed: Int
}

/// `POST /v1/taunts/check`.
nonisolated struct TauntCheckRequest: Codable, Sendable {
    var text: String
}

nonisolated struct TauntCheckResult: Codable, Hashable, Sendable {
    var allowed: Bool
    var reason: String?
}

/// `POST /v1/reports`.
nonisolated struct ReportRequest: Codable, Sendable {
    enum TargetType: String, Codable, Sendable { case taunt, player, photo }
    var targetType: TargetType
    var targetId: String
    var reason: String
}

/// `POST /v1/blocks`.
nonisolated struct BlockRequest: Codable, Sendable {
    var playerId: PlayerID
}

/// `POST /v1/receipts`.
nonisolated struct ReceiptRequest: Codable, Sendable {
    var gameId: GameID
    var toPlayerId: PlayerID
    var receiptKey: String
}

/// `POST /v1/push/tokens`.
nonisolated struct PushTokenRequest: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case apns, liveactivity }
    var token: String
    var kind: Kind
    var gameId: GameID?

    private enum CodingKeys: String, CodingKey { case token, kind, gameId }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(gameId, forKey: .gameId) // omitted when nil
    }
}

/// `{ok: true}` from the write endpoints.
nonisolated struct OKResponse: Codable, Hashable, Sendable {
    var ok: Bool
}
