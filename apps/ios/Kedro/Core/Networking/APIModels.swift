import Foundation

// Request and response shapes of the Kedro API contract. Field names are the JSON keys.

/// `POST /v1/ops` body. `invites` maps a game ID (lowercase) to the table's current invite code,
/// which the server requires before it seats a phone that seats itself (apps/api `inviteRequired`).
nonisolated struct OpsUpload: Encodable, Sendable {
    var ops: [GameOperation]
    var invites: [String: String]?

    private enum CodingKeys: String, CodingKey { case ops, invites }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ops, forKey: .ops)
        if let invites, !invites.isEmpty { try container.encode(invites, forKey: .invites) }
    }
}

/// `POST /v1/ops` response. Idempotent by `opId`: ops already stored come back as duplicates.
/// An op in neither list was refused by the server (`rejected` says why, when the server says).
nonisolated struct OpsUploadResult: Codable, Hashable, Sendable {
    nonisolated struct Rejection: Codable, Hashable, Sendable {
        var opId: UUID?
        var reason: String
        var message: String?
    }

    var accepted: [UUID]
    var duplicates: [UUID]
    var rejected: [Rejection] = []

    init(accepted: [UUID], duplicates: [UUID], rejected: [Rejection] = []) {
        self.accepted = accepted
        self.duplicates = duplicates
        self.rejected = rejected
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accepted = try container.decode([UUID].self, forKey: .accepted)
        duplicates = try container.decode([UUID].self, forKey: .duplicates)
        rejected = (try? container.decodeIfPresent([Rejection].self, forKey: .rejected)) ?? []
    }

    /// Every op the server now holds (accepted now or earlier).
    var stored: Set<UUID> { Set(accepted).union(duplicates) }

    /// Refused only because this phone's clock is ahead of the server's: worth sending again later.
    var clockAhead: Set<UUID> { Set(rejected.filter { $0.reason == "clockAhead" }.compactMap(\.opId)) }
}

/// `PUT /v1/games/:gameId/invite-key` body: the table's invite-code key (`TableKey.inviteKey`), base64url.
nonisolated struct InviteKeyRequest: Codable, Sendable {
    var key: String
}

/// `GET /v1/players/me/games`: every game the account is seated in, claimed guest seats included.
nonisolated struct MyGamesResponse: Codable, Sendable {
    nonisolated struct Game: Codable, Hashable, Sendable {
        var gameId: GameID
        var status: String
        var finishedAt: Date?
    }

    var games: [Game]
    var claimedGuestIds: [GuestID] = []

    private enum CodingKeys: String, CodingKey { case games, claimedGuestIds }

    init(games: [Game], claimedGuestIds: [GuestID] = []) {
        self.games = games
        self.claimedGuestIds = claimedGuestIds
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        games = try container.decode([Game].self, forKey: .games)
        claimedGuestIds = (try? container.decodeIfPresent([GuestID].self, forKey: .claimedGuestIds)) ?? []
    }
}

/// `GET /v1/players/:playerId/profile`: the server's record of one player, the same on every phone.
nonisolated struct PlayerProfileResponse: Codable, Hashable, Sendable {
    nonisolated struct Stats: Codable, Hashable, Sendable {
        var gamesPlayed: Int
        var wins: Int
        var winRate: Double
        var avgScore: Double
        var knocks: Int
        var knocksLanded: Int
        var knockSuccess: Double?
    }

    var player: PlayerSummary
    var rating: Int?
    var globalRank: Int?
    var stats: Stats?
}

/// `GET /v1/leaderboard` response (packages/shared `LeaderboardResponse`).
nonisolated struct LeaderboardResponse: Codable, Hashable, Sendable {
    nonisolated struct Row: Codable, Hashable, Sendable {
        var rank: Int?
        var player: PlayerSummary
        var value: Double?
        var rating: Int
        var gamesPlayed: Int
        var wins: Int
        var winRate: Double
        var avgScore: Double
        var knocks: Int
        var knocksLanded: Int
        var knockSuccess: Double?
        var isMe: Bool
    }

    nonisolated struct NotYetRanked: Codable, Hashable, Sendable {
        var player: PlayerSummary
        var gamesPlayed: Int
        var gamesToRank: Int
        var isMe: Bool
    }

    var scope: String
    var sort: String
    var rows: [Row]
    var notYetRanked: [NotYetRanked]
    var notYetRankedCount: Int
}

/// `PUT /v1/players/me/photo` response: the avatar to put in the profile and in seats.
nonisolated struct PhotoUploadResponse: Codable, Sendable {
    var avatar: Avatar
}

/// `POST /v1/link/attestations` body and response (table-link identity, design §5.3).
nonisolated struct LinkAttestationRequest: Codable, Sendable {
    var deviceId: DeviceID
    var publicKey: String
}

nonisolated struct LinkAttestationResponse: Codable, Sendable {
    var attestation: String
    var expiresAt: Date
}

/// `GET /link/key`: the server's Ed25519 attestation key, raw 32 bytes base64url.
nonisolated struct LinkKeyResponse: Codable, Sendable {
    var publicKey: String
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
    /// The displayed title (`TI-xx`). Omitted keeps the server's current one.
    var titleID: String?

    private enum CodingKeys: String, CodingKey {
        case displayName, handle, avatar
        case titleID = "titleId"
    }
}

/// `GET /v1/players/search` response.
nonisolated struct PlayerSearchResult: Codable, Sendable {
    var players: [PlayerSummary]
}

/// `GET /v1/players` response: one page of every player A–Z.
nonisolated struct PlayerDirectoryResult: Codable, Sendable {
    var players: [PlayerSummary]
    var next: String?
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
nonisolated struct BlockPlayerBody: Codable, Sendable {
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

/// `GET /v1/games/:gameId/live-activity` response.
nonisolated struct LiveActivityChannelResponse: Codable, Hashable, Sendable {
    var channelId: String?
}
