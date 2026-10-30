import Foundation

/// Everything phones at a table say to each other over the link (design §5.2). Each message is
/// one frame (`LinkFrame`): a 4-byte big-endian length, then the message as JSON.
///
/// The conversation, star topology (one hub, everyone else a spoke):
/// 1. Spoke → hub: `hello` (join or peek).
/// 2. Hub → spoke: `welcome` (admitted), `pending` (Ask to Sit: waiting on a seated phone) or `refused`.
/// 3. Both: `inventory` (every opId held); each answers with the `operations` the other lacks.
/// 4. Live: `operations` batches; the hub relays each batch to every other member. `members`
///    whenever someone comes or goes (spokes use it to elect the next hub).
/// 5. `ping`/`pong` every few seconds; silence for `TableLink.peerTimeout` drops the peer.
nonisolated enum LinkMessage: Hashable, Sendable, Codable {
    case hello(LinkHello)
    case welcome(LinkWelcome)
    case pending(requestID: UUID)
    case refused(LinkRefusal)
    case members([LinkMember])
    case inventory(game: GameID, opIDs: [UUID])
    case operations([GameOperation])
    /// Hub → members: someone is asking to sit (J-02). Any seated phone may answer.
    case seatRequest(SeatRequest)
    /// Member → hub: the answer to a seat request.
    case seatDecision(requestID: UUID, admit: Bool)
    /// Hub → members: a request was answered (dismiss the prompt).
    case seatRequestResolved(requestID: UUID)
    /// A Nearby Interaction discovery token (archived `NIDiscoveryToken`), for distance.
    case nearbyToken(Data)
    case ping(UInt64)
    case pong(UInt64)
    case goodbye
}

/// The first message on every connection.
nonisolated struct LinkHello: Hashable, Sendable, Codable {
    nonisolated enum Purpose: String, Hashable, Sendable, Codable {
        /// Sit at (or watch) the table: exchange operations.
        case join
        /// Look only: the Table card's distance (Nearby Interaction). No operations.
        case peek
    }

    /// Bumped on incompatible changes; the hub refuses other versions.
    static let currentVersion = 1

    var version: Int = LinkHello.currentVersion
    var purpose: Purpose
    var game: GameID
    var device: DeviceID
    var person: PlayerRef?
    var displayName: String
    /// Proves this phone was admitted before: `TableKey.membershipProof`. nil for a first visit.
    var proof: Data?
}

nonisolated struct LinkWelcome: Hashable, Sendable, Codable {
    var hub: DeviceID
    /// The table secret, so this phone can prove membership to any future hub.
    var tableSecret: Data
    var members: [LinkMember]
}

nonisolated enum LinkRefusal: String, Hashable, Sendable, Codable {
    case wrongGame
    case unsupportedVersion
    case declined
    case tableFull
}

/// A phone on the link.
nonisolated struct LinkMember: Hashable, Sendable, Codable, Identifiable {
    var device: DeviceID
    var person: PlayerRef?
    var displayName: String
    /// The person's seat order at the table (clockwise), nil for a watcher.
    var seatOrder: Int?
    var isHub: Bool

    var id: DeviceID { device }

    /// Hub election order: the lowest online seat, watchers last, ties by device ID.
    var electionRank: HubRank { HubRank(seatOrder: seatOrder, device: device) }
}

/// Orders candidates for hub. Lower is better.
nonisolated struct HubRank: Comparable, Hashable, Sendable {
    var seatOrder: Int?
    var device: DeviceID

    static func < (lhs: HubRank, rhs: HubRank) -> Bool {
        let left = lhs.seatOrder ?? Int.max
        let right = rhs.seatOrder ?? Int.max
        if left != right { return left < right }
        return lhs.device.uuidString < rhs.device.uuidString
    }
}

/// Someone at the door who isn't known to the table (design §5.3, J-02).
nonisolated struct SeatRequest: Hashable, Sendable, Codable, Identifiable {
    var id: UUID
    var game: GameID
    var device: DeviceID
    var person: PlayerRef?
    var displayName: String
}
