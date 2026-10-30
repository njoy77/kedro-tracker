import Foundation

/// One entry in a game's append-only operation log (design §11). Everything that happens in a
/// game is an operation; `GameState.fold` turns the log into what the table shows.
///
/// Operations are created by `GameSession.send(_:)`, stored by `GameStore`, exchanged by
/// `OperationTransport`, and ingested idempotently by the API (`POST /v1/ops`, keyed by `opId`).
///
/// JSON (the API contract; encode with `KedroJSON.encoder`):
/// ```json
/// {
///   "opId": "4f6c…",                      // lowercase UUID, idempotency key
///   "gameId": "8f14…",
///   "deviceId": "1c2d…",
///   "hlc": {"wallMs": 1761700000000, "counter": 0, "node": "1c2d…"},
///   "actorPlayerId": "a1b2…",             // null for guest-mode phones and system actions
///   "type": "RoundRecorded",
///   "payload": {"round": {"number": 5, "hands": {"p:…": 2}, "knocker": "p:…"}}
/// }
/// ```
nonisolated struct GameOperation: Hashable, Sendable, Identifiable, Codable {
    let opId: UUID
    let gameId: GameID
    let deviceId: DeviceID
    let hlc: HLC
    /// The signed-in player who did it. nil for a guest-mode phone (attributed through the seat
    /// linked to `deviceId`) or a system action such as the 15-minute auto-finish.
    let actorPlayerId: PlayerID?
    let payload: OperationPayload

    var id: UUID { opId }
    var type: OperationType { payload.type }

    init(
        opId: UUID = UUID(),
        gameId: GameID,
        deviceId: DeviceID,
        hlc: HLC,
        actorPlayerId: PlayerID?,
        payload: OperationPayload
    ) {
        self.opId = opId
        self.gameId = gameId
        self.deviceId = deviceId
        self.hlc = hlc
        self.actorPlayerId = actorPlayerId
        self.payload = payload
    }

    /// The fold order: HLC, then device ID, then operation ID (all total, so every device agrees).
    static func foldOrder(_ lhs: GameOperation, _ rhs: GameOperation) -> Bool {
        if lhs.hlc != rhs.hlc { return lhs.hlc < rhs.hlc }
        if lhs.deviceId != rhs.deviceId { return lhs.deviceId.uuidString < rhs.deviceId.uuidString }
        return lhs.opId.uuidString < rhs.opId.uuidString
    }

    private enum CodingKeys: String, CodingKey {
        case opId, gameId, deviceId, hlc, actorPlayerId, type, payload
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let opString = try container.decode(String.self, forKey: .opId)
        guard let opId = UUID(uuidString: opString) else {
            throw DecodingError.dataCorruptedError(forKey: .opId, in: container, debugDescription: "Invalid opId")
        }
        self.opId = opId
        gameId = try container.decode(GameID.self, forKey: .gameId)
        deviceId = try container.decode(DeviceID.self, forKey: .deviceId)
        hlc = try container.decode(HLC.self, forKey: .hlc)
        actorPlayerId = try container.decodeIfPresent(PlayerID.self, forKey: .actorPlayerId)
        let type = try container.decode(OperationType.self, forKey: .type)
        payload = try OperationPayload(type: type, from: container.superDecoder(forKey: .payload))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(opId.uuidString.lowercased(), forKey: .opId)
        try container.encode(gameId, forKey: .gameId)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(hlc, forKey: .hlc)
        try container.encode(actorPlayerId, forKey: .actorPlayerId) // explicit null
        try container.encode(type, forKey: .type)
        try payload.encode(to: container.superEncoder(forKey: .payload))
    }
}

/// The `type` field. Raw values are the wire names and must match the API.
nonisolated enum OperationType: String, Hashable, Sendable, Codable, CaseIterable {
    case gameCreated = "GameCreated"
    case gameStarted = "GameStarted"
    case gameConfigured = "GameConfigured"
    case playerSeated = "PlayerSeated"
    case seatRemoved = "SeatRemoved"
    case scorekeeperChanged = "ScorekeeperChanged"
    case roundRecorded = "RoundRecorded"
    case roundEdited = "RoundEdited"
    case roundUndone = "RoundUndone"
    case knockMarked = "KnockMarked"
    case knockerProposed = "KnockerProposed"
    case knockerResolved = "KnockerResolved"
    case handReported = "HandReported"
    case roundsChanged = "RoundsChanged"
    case dealerChanged = "DealerChanged"
    case tauntSent = "TauntSent"
    case tauntRetracted = "TauntRetracted"
    case reactionAdded = "ReactionAdded"
    case receiptSent = "ReceiptSent"
    case tableSpeakerClaimed = "TableSpeakerClaimed"
    case gameFinished = "GameFinished"
    case gameAbandoned = "GameAbandoned"
    case gameRestored = "GameRestored"

    /// Operations that change scores, seats or the game's shape. These are refused after a game is
    /// finished or abandoned (and surface as late operations).
    var isStateChanging: Bool {
        switch self {
        case .tauntSent, .tauntRetracted, .reactionAdded, .receiptSent, .tableSpeakerClaimed: false
        default: true
        }
    }
}

/// Payload structs, one per operation type. Field names are the JSON keys.
nonisolated enum Op {
    /// The lobby opened. `{"config":{…},"host":"p:…"}`
    struct GameCreated: Hashable, Sendable, Codable {
        var config: GameConfig
        var host: SeatID
    }

    /// The host tapped Deal: seat order and first dealer are fixed and every phone flips into
    /// the Table. `{"seatOrder":["p:…",…],"firstDealer":"p:…"}`
    struct GameStarted: Hashable, Sendable, Codable {
        var seatOrder: [SeatID]
        var firstDealer: SeatID
    }

    /// Adds a seat, or updates an existing one (same `seat.player`): reorder, link a phone,
    /// assign a reporter, update the language level. New seats are refused after Round 1 and
    /// beyond 8 seats. `{"seat":{…Seat…}}`
    struct PlayerSeated: Hashable, Sendable, Codable {
        var seat: Seat
    }

    /// Removes a seat before Round 1 (logged). `{"seatId":"g:…"}`
    struct SeatRemoved: Hashable, Sendable, Codable {
        var seatId: SeatID
    }

    /// Hand off scorekeeping (logged). `{"seatId":"p:…"}`
    struct ScorekeeperChanged: Hashable, Sendable, Codable {
        var seatId: SeatID
    }

    /// A round saved from the number pad (scorekeeper mode). `round.number` must be the next
    /// round; a second record for an existing number is a duplicate (the earlier is kept).
    /// `{"round":{…Round…}}`
    struct RoundRecorded: Hashable, Sendable, Codable {
        var round: Round
    }

    /// A correction: the round's complete new hands and knocker (logged with before → after).
    /// `{"round":{…Round…}}`
    struct RoundEdited: Hashable, Sendable, Codable {
        var round: Round
    }

    /// Removes the latest round (the 5-second Undo). Only the latest round can be undone.
    /// `{"roundNumber":6}`
    struct RoundUndone: Hashable, Sendable, Codable {
        var roundNumber: Int
    }

    /// Live knock (design §7.5). `knocker: null` clears the mark (Undo).
    /// `{"roundNumber":6,"knocker":"g:…"}`
    struct KnockMarked: Hashable, Sendable, Codable {
        var roundNumber: Int
        var knocker: SeatID?
    }

    /// Self-report: someone proposes who knocked when nobody or several claimed it.
    /// `{"roundNumber":6,"knocker":"p:…"}`
    struct KnockerProposed: Hashable, Sendable, Codable {
        var roundNumber: Int
        var knocker: SeatID
    }

    /// Self-report: the knocker is settled (proposal committed, or confirmed).
    /// `{"roundNumber":6,"knocker":"p:…"}`
    struct KnockerResolved: Hashable, Sendable, Codable {
        var roundNumber: Int
        var knocker: SeatID
    }

    /// Lobby only (design §5.6): the table word, scoring mode and house voice cap, which
    /// `GameCreated` set. Replaces all three (no `houseVoiceCap` clears the cap); refused after
    /// Deal. `{"tableWord":"Cold Deck","scoringMode":"scorekeeper","houseVoiceCap":"clean"}`
    struct GameConfigured: Hashable, Sendable, Codable {
        var tableWord: String
        var scoringMode: ScoringMode
        var houseVoiceCap: LanguageLevel?
    }

    /// Self-report: one seat's hand (by that player or their reporter). When every seat has
    /// reported and the knocker is settled, the fold completes the round.
    /// `{"roundNumber":6,"seatId":"p:…","hand":7,"knocked":false}`
    struct HandReported: Hashable, Sendable, Codable {
        var roundNumber: Int
        var seatId: SeatID
        var hand: Int
        var knocked: Bool
        /// The knock was inherent (they played all four cards; hand 0).
        var inherent: Bool?
    }

    /// Extend (or shorten) the planned rounds (logged). `{"plannedRounds":8}`
    struct RoundsChanged: Hashable, Sendable, Codable {
        var plannedRounds: Int
    }

    /// Who deals `roundNumber` (a correction, logged). Later rounds pass left from here.
    /// `{"roundNumber":6,"dealer":"p:…"}`
    struct DealerChanged: Hashable, Sendable, Codable {
        var roundNumber: Int
        var dealer: SeatID
    }

    /// A taunt (design §8.1). `from` is nil for watchers, who are identified by `fromName`.
    /// `{"tauntId":"…","roundNumber":6,"from":"p:…","fromName":"Ana","target":{…},"content":{…}}`
    struct TauntSent: Hashable, Sendable, Codable {
        var tauntId: UUID
        var roundNumber: Int
        var from: SeatID?
        var fromName: String
        var target: TauntTarget
        var content: TauntContent
    }

    /// A custom taunt that failed the server check is retracted from every phone (design §11).
    /// `{"tauntId":"…","reason":"filter"}`
    struct TauntRetracted: Hashable, Sendable, Codable {
        var tauntId: UUID
        var reason: String?
    }

    /// One reaction per player per round; a second one replaces the first.
    /// `{"roundNumber":5,"seatId":"p:…","reaction":"fire"}`
    struct ReactionAdded: Hashable, Sendable, Codable {
        var roundNumber: Int
        var seatId: SeatID
        var reaction: Reaction
    }

    /// One receipt per rival per finished game (design §8.5). Allowed after finish.
    /// `{"fromSeat":"p:…","toSeat":"p:…","receiptKey":"RC-02"}`
    struct ReceiptSent: Hashable, Sendable, Codable {
        var fromSeat: SeatID
        var toSeat: SeatID
        var receiptKey: String
    }

    /// "Be the table speaker" (design §3.8). `{"deviceId":"…"}`
    struct TableSpeakerClaimed: Hashable, Sendable, Codable {
        var deviceId: DeviceID
    }

    /// Locks the game. `finalRounds` is the finisher's view of every round and is authoritative:
    /// every phone shows exactly these rounds, and anything that disagrees is surfaced as late.
    /// `{"reason":"completed","finalRounds":[{…Round…}]}`
    struct GameFinished: Hashable, Sendable, Codable {
        var reason: FinishReason
        var finalRounds: [Round]
    }

    /// Voids the game for stats (logged; restorable for 15 minutes). `{}`
    struct GameAbandoned: Hashable, Sendable, Codable {}

    /// Undoes an abandon within 15 minutes. `{}`
    struct GameRestored: Hashable, Sendable, Codable {}
}

/// Why a game ended. JSON: `"completed"` | `"endedEarly"` | `"autoFinished"`.
nonisolated enum FinishReason: String, Hashable, Sendable, Codable {
    /// All planned rounds played and Finish Game tapped.
    case completed
    /// End Early (counts fully in stats).
    case endedEarly
    /// Nobody touched the finish gate for 15 minutes (G-02).
    case autoFinished
}

/// A typed operation payload.
nonisolated enum OperationPayload: Hashable, Sendable {
    case gameCreated(Op.GameCreated)
    case gameStarted(Op.GameStarted)
    case gameConfigured(Op.GameConfigured)
    case playerSeated(Op.PlayerSeated)
    case seatRemoved(Op.SeatRemoved)
    case scorekeeperChanged(Op.ScorekeeperChanged)
    case roundRecorded(Op.RoundRecorded)
    case roundEdited(Op.RoundEdited)
    case roundUndone(Op.RoundUndone)
    case knockMarked(Op.KnockMarked)
    case knockerProposed(Op.KnockerProposed)
    case knockerResolved(Op.KnockerResolved)
    case handReported(Op.HandReported)
    case roundsChanged(Op.RoundsChanged)
    case dealerChanged(Op.DealerChanged)
    case tauntSent(Op.TauntSent)
    case tauntRetracted(Op.TauntRetracted)
    case reactionAdded(Op.ReactionAdded)
    case receiptSent(Op.ReceiptSent)
    case tableSpeakerClaimed(Op.TableSpeakerClaimed)
    case gameFinished(Op.GameFinished)
    case gameAbandoned(Op.GameAbandoned)
    case gameRestored(Op.GameRestored)

    var type: OperationType {
        switch self {
        case .gameCreated: .gameCreated
        case .gameStarted: .gameStarted
        case .gameConfigured: .gameConfigured
        case .playerSeated: .playerSeated
        case .seatRemoved: .seatRemoved
        case .scorekeeperChanged: .scorekeeperChanged
        case .roundRecorded: .roundRecorded
        case .roundEdited: .roundEdited
        case .roundUndone: .roundUndone
        case .knockMarked: .knockMarked
        case .knockerProposed: .knockerProposed
        case .knockerResolved: .knockerResolved
        case .handReported: .handReported
        case .roundsChanged: .roundsChanged
        case .dealerChanged: .dealerChanged
        case .tauntSent: .tauntSent
        case .tauntRetracted: .tauntRetracted
        case .reactionAdded: .reactionAdded
        case .receiptSent: .receiptSent
        case .tableSpeakerClaimed: .tableSpeakerClaimed
        case .gameFinished: .gameFinished
        case .gameAbandoned: .gameAbandoned
        case .gameRestored: .gameRestored
        }
    }

    init(type: OperationType, from decoder: any Decoder) throws {
        switch type {
        case .gameCreated: self = .gameCreated(try .init(from: decoder))
        case .gameStarted: self = .gameStarted(try .init(from: decoder))
        case .gameConfigured: self = .gameConfigured(try .init(from: decoder))
        case .playerSeated: self = .playerSeated(try .init(from: decoder))
        case .seatRemoved: self = .seatRemoved(try .init(from: decoder))
        case .scorekeeperChanged: self = .scorekeeperChanged(try .init(from: decoder))
        case .roundRecorded: self = .roundRecorded(try .init(from: decoder))
        case .roundEdited: self = .roundEdited(try .init(from: decoder))
        case .roundUndone: self = .roundUndone(try .init(from: decoder))
        case .knockMarked: self = .knockMarked(try .init(from: decoder))
        case .knockerProposed: self = .knockerProposed(try .init(from: decoder))
        case .knockerResolved: self = .knockerResolved(try .init(from: decoder))
        case .handReported: self = .handReported(try .init(from: decoder))
        case .roundsChanged: self = .roundsChanged(try .init(from: decoder))
        case .dealerChanged: self = .dealerChanged(try .init(from: decoder))
        case .tauntSent: self = .tauntSent(try .init(from: decoder))
        case .tauntRetracted: self = .tauntRetracted(try .init(from: decoder))
        case .reactionAdded: self = .reactionAdded(try .init(from: decoder))
        case .receiptSent: self = .receiptSent(try .init(from: decoder))
        case .tableSpeakerClaimed: self = .tableSpeakerClaimed(try .init(from: decoder))
        case .gameFinished: self = .gameFinished(try .init(from: decoder))
        case .gameAbandoned: self = .gameAbandoned(try .init(from: decoder))
        case .gameRestored: self = .gameRestored(try .init(from: decoder))
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .gameCreated(let p): try p.encode(to: encoder)
        case .gameStarted(let p): try p.encode(to: encoder)
        case .gameConfigured(let p): try p.encode(to: encoder)
        case .playerSeated(let p): try p.encode(to: encoder)
        case .seatRemoved(let p): try p.encode(to: encoder)
        case .scorekeeperChanged(let p): try p.encode(to: encoder)
        case .roundRecorded(let p): try p.encode(to: encoder)
        case .roundEdited(let p): try p.encode(to: encoder)
        case .roundUndone(let p): try p.encode(to: encoder)
        case .knockMarked(let p): try p.encode(to: encoder)
        case .knockerProposed(let p): try p.encode(to: encoder)
        case .knockerResolved(let p): try p.encode(to: encoder)
        case .handReported(let p): try p.encode(to: encoder)
        case .roundsChanged(let p): try p.encode(to: encoder)
        case .dealerChanged(let p): try p.encode(to: encoder)
        case .tauntSent(let p): try p.encode(to: encoder)
        case .tauntRetracted(let p): try p.encode(to: encoder)
        case .reactionAdded(let p): try p.encode(to: encoder)
        case .receiptSent(let p): try p.encode(to: encoder)
        case .tableSpeakerClaimed(let p): try p.encode(to: encoder)
        case .gameFinished(let p): try p.encode(to: encoder)
        case .gameAbandoned(let p): try p.encode(to: encoder)
        case .gameRestored(let p): try p.encode(to: encoder)
        }
    }
}

/// The JSON coders every Kedro client uses (operations, API bodies, persistence): ISO 8601 dates,
/// sorted keys for stable output.
nonisolated enum KedroJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
