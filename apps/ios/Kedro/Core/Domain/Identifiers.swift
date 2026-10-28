import Foundation

/// A type-safe UUID identifier. The phantom `Tag` keeps a `PlayerID` from being passed where a
/// `GameID` is expected.
///
/// JSON: a lowercase UUID string, e.g. `"8f14e45f-ceea-467f-a9b0-3a1c4b2d5e6f"`.
nonisolated struct Identifier<Tag>: Hashable, Sendable, Codable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        rawValue = uuid
    }

    /// Lowercase UUID string, the form used in JSON and in `SeatID`s.
    var uuidString: String { rawValue.uuidString.lowercased() }
    var description: String { uuidString }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let uuid = UUID(uuidString: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid UUID \(string)")
        }
        rawValue = uuid
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuidString)
    }
}

nonisolated enum PlayerTag {}
nonisolated enum GuestTag {}
nonisolated enum GameTag {}
nonisolated enum DeviceTag {}

/// A signed-up Kedro player (the Supabase auth user ID).
typealias PlayerID = Identifier<PlayerTag>
/// A guest identity: a name at the table with no account. Claimable later (PRD §3.2).
typealias GuestID = Identifier<GuestTag>
/// One game (a "table").
typealias GameID = Identifier<GameTag>
/// One installation of Kedro on one phone. Generated once and kept in `UserDefaults`.
typealias DeviceID = Identifier<DeviceTag>

/// Who someone is, independent of any game: a player with an account, or a guest.
///
/// JSON: `{"kind":"player","id":"<uuid>"}` or `{"kind":"guest","id":"<uuid>"}`.
nonisolated enum PlayerRef: Hashable, Sendable, Codable, CustomStringConvertible {
    case player(PlayerID)
    case guest(GuestID)

    /// The seat this person occupies in any game. Deterministic, so the same person always has
    /// the same `SeatID` across games, which makes stats a simple group-by.
    var seatID: SeatID { SeatID(self) }

    var playerID: PlayerID? {
        if case .player(let id) = self { id } else { nil }
    }

    var guestID: GuestID? {
        if case .guest(let id) = self { id } else { nil }
    }

    var isGuest: Bool { guestID != nil }

    var description: String { seatID.rawValue }

    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "player": self = .player(try container.decode(PlayerID.self, forKey: .id))
        case "guest": self = .guest(try container.decode(GuestID.self, forKey: .id))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown kind \(kind)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .player(let id):
            try container.encode("player", forKey: .kind)
            try container.encode(id, forKey: .id)
        case .guest(let id):
            try container.encode("guest", forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }
}

/// Identifies a seat at a table: `"p:<playerId>"` for a player or `"g:<guestId>"` for a guest.
///
/// Derived from `PlayerRef`, never generated. Used as the key of round hands, so JSON encodes
/// `[SeatID: Int]` as an object: `{"p:8f14…":9,"g:1c2d…":15}`.
nonisolated struct SeatID: Hashable, Sendable, Codable, CodingKeyRepresentable, Comparable, CustomStringConvertible {
    /// The person in this seat.
    let playerRef: PlayerRef

    init(_ ref: PlayerRef) {
        playerRef = ref
    }

    /// Parses `"p:<uuid>"` or `"g:<uuid>"`.
    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "p":
            guard let id = PlayerID(uuidString: parts[1]) else { return nil }
            playerRef = .player(id)
        case "g":
            guard let id = GuestID(uuidString: parts[1]) else { return nil }
            playerRef = .guest(id)
        default:
            return nil
        }
    }

    var rawValue: String {
        switch playerRef {
        case .player(let id): "p:" + id.uuidString
        case .guest(let id): "g:" + id.uuidString
        }
    }

    var description: String { rawValue }

    static func < (lhs: SeatID, rhs: SeatID) -> Bool { lhs.rawValue < rhs.rawValue }

    // MARK: Codable (a plain string)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let id = SeatID(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid seat ID \(raw)")
        }
        self = id
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: CodingKeyRepresentable (dictionary keys)

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    var codingKey: any CodingKey { Key(stringValue: rawValue) }

    init?<T: CodingKey>(codingKey: T) {
        self.init(rawValue: codingKey.stringValue)
    }
}
