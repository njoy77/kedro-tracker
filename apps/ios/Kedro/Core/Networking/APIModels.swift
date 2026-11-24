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
    /// Guest → the account that claimed it, for every claimed guest at these tables (the
    /// caller's own included). nil from older servers, which don't send it.
    var claims: [GuestID: PlayerID]?

    private enum CodingKeys: String, CodingKey { case games, claimedGuestIds, claims }

    init(games: [Game], claimedGuestIds: [GuestID] = [], claims: [GuestID: PlayerID]? = nil) {
        self.games = games
        self.claimedGuestIds = claimedGuestIds
        self.claims = claims
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        games = try container.decode([Game].self, forKey: .games)
        claimedGuestIds = (try? container.decodeIfPresent([GuestID].self, forKey: .claimedGuestIds)) ?? []
        // JSON object keys are strings; malformed pairs are skipped rather than failing the list.
        claims = (try? container.decodeIfPresent([String: String].self, forKey: .claims)).flatMap { $0 }.map { pairs in
            Dictionary(pairs.compactMap { guest, player in
                guard let guest = GuestID(uuidString: guest), let player = PlayerID(uuidString: player) else { return nil }
                return (guest, player)
            }, uniquingKeysWith: { first, _ in first })
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(games, forKey: .games)
        try container.encode(claimedGuestIds, forKey: .claimedGuestIds)
        if let claims {
            try container.encode(Dictionary(uniqueKeysWithValues: claims.map { ($0.key.uuidString, $0.value.uuidString) }), forKey: .claims)
        }
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
        /// 🐴 taps across counted games, and per game. Optional: older servers don't send them.
        var neighs: Int?
        var neighsPerGame: Double?
    }

    var player: PlayerSummary
    var rating: Int?
    var globalRank: Int?
    var stats: Stats?
}

/// `GET /v1/players/:playerId/progression` (packages/shared `PlayerProgressionResponse`): a player's
/// badges and titles replayed on the server from every game they've finished, so other people's
/// profiles show what their own phone shows. Unknown badge or title IDs (a newer server's) are
/// skipped by the screens; fields this app doesn't use are ignored.
nonisolated struct PlayerProgressionResponse: Codable, Hashable, Sendable {
    nonisolated struct EarnedBadge: Codable, Hashable, Sendable {
        var badge: String
        var gameId: GameID?
        var tableWord: String?
        var roundNumber: Int?
        var earnedAt: Date?
    }

    nonisolated struct Titles: Codable, Hashable, Sendable {
        var earned: [String]
        var held: [String]
        var display: String?
    }

    var playerId: PlayerID
    var badges: [EarnedBadge]
    var titles: Titles
    var hallOfShameEntries: Int

    /// Earned badges as the awards the badge screens render (no replay position: server-side).
    var awards: [BadgeID: BadgeAward] {
        Dictionary(badges.compactMap { earned in
            BadgeID(rawValue: earned.badge).map { id in
                (id, BadgeAward(badge: id, gameID: earned.gameId, tableWord: earned.tableWord, roundNumber: earned.roundNumber, date: earned.earnedAt))
            }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The title shown under their name.
    var displayTitle: TitleID? { titles.display.flatMap(TitleID.init(rawValue:)) }
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
        /// 🐴 taps across counted games, and per game (shown, not sortable). Optional: older
        /// servers don't send them; read as 0.
        var neighs: Int?
        var neighsPerGame: Double?
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

/// `GET /v1/records` response (packages/shared `RecordsResponse`): every record's top holders.
nonisolated struct RecordsResponse: Codable, Hashable, Sendable {
    nonisolated struct Row: Codable, Hashable, Sendable {
        nonisolated struct Game: Codable, Hashable, Sendable {
            var gameId: GameID
            var tableWord: String
            var finishedAt: Date
        }

        var rank: Int
        var player: PlayerSummary
        var value: Int
        var isMe: Bool
        var game: Game?
    }

    nonisolated struct Record: Codable, Hashable, Sendable {
        /// A `RecordKind` raw value; kinds this app doesn't know are skipped.
        var kind: String
        var rows: [Row]
    }

    var scope: String
    var records: [Record]
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

/// `GET /v1/games/:gameId/ops` response, decoded lossily (`OperationsPage`).
typealias OpsPage = OperationsPage

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

/// `GET /v1/players/me/played-with` response: everyone the account shared a counted game with,
/// guest history they've since claimed included.
nonisolated struct PlayedWithResult: Codable, Sendable {
    nonisolated struct Row: Codable, Sendable {
        var player: PlayerSummary
        var gamesTogether: Int
        var lastPlayedAt: Date?
    }

    var players: [Row]
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
