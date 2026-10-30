import Foundation
import Network

/// What a table's hub advertises in its Bonjour TXT record (`_kedro-table._tcp`, design §5.2):
/// the table ID, host, seat count, round state and table word, plus who's seated and which phone
/// is the hub (for failover). Kept well under ~1.3 KB so it fits a single mDNS packet over AWDL.
nonisolated struct TableAdvertisement: Hashable, Sendable {
    nonisolated struct SeatedPlayer: Hashable, Sendable {
        var id: PlayerID
        var displayName: String
        var handle: Handle?
    }

    static let serviceType = "_kedro-table._tcp"
    static let version = 1
    static let maxSeatedListed = 8

    var game: GameID
    var tableWord: String
    var hostName: String
    var hostPlayer: PlayerID?
    var hostHandle: Handle?
    var hostAvatar: Avatar?
    var seatCount: Int
    var guestCount: Int
    var roundsPlayed: Int
    var isStarted: Bool
    /// Finished or abandoned: phones may still trade reactions and receipts, but nobody new sits.
    var isFinished: Bool = false
    var seated: [SeatedPlayer]
    /// The phone currently acting as hub, and its seat order (nil for a watcher).
    var hub: DeviceID
    var hubSeatOrder: Int?

    var hubRank: HubRank { HubRank(seatOrder: hubSeatOrder, device: hub) }

    /// The Bonjour instance name: unique per game and readable in diagnostics.
    var serviceName: String { "Kedro \(game.uuidString.prefix(8))" }

    // MARK: From a game

    /// Builds the advertisement for a game this phone hubs. `table` (from the lobby's
    /// `TableDiscovery.advertise`) overrides the host name and word when given.
    init(state: GameState, table: AdvertisedTable?, hub: DeviceID, hubSeatOrder: Int?) {
        let host = state.hostSeat.flatMap { state.seat($0) } ?? state.seats.first
        game = state.gameID
        tableWord = table?.tableWord ?? state.config.tableWord
        hostName = table?.hostName ?? host?.displayName ?? "Someone"
        hostPlayer = host?.player.playerID
        hostHandle = host?.handle
        hostAvatar = host?.avatar
        seatCount = max(table?.seatCount ?? 0, state.seats.count)
        guestCount = state.seats.filter(\.isGuest).count
        roundsPlayed = max(table?.roundsPlayed ?? 0, state.rounds.count)
        isStarted = state.status != .lobby
        isFinished = !state.status.isLive
        seated = state.seats.prefix(Self.maxSeatedListed).compactMap { seat in
            seat.player.playerID.map { SeatedPlayer(id: $0, displayName: seat.displayName, handle: seat.handle) }
        }
        self.hub = hub
        self.hubSeatOrder = hubSeatOrder
    }

    init(
        game: GameID, tableWord: String, hostName: String, hostPlayer: PlayerID? = nil, hostHandle: Handle? = nil,
        hostAvatar: Avatar? = nil, seatCount: Int, guestCount: Int = 0, roundsPlayed: Int = 0, isStarted: Bool = false,
        seated: [SeatedPlayer] = [], hub: DeviceID, hubSeatOrder: Int? = 0
    ) {
        self.game = game
        self.tableWord = tableWord
        self.hostName = hostName
        self.hostPlayer = hostPlayer
        self.hostHandle = hostHandle
        self.hostAvatar = hostAvatar
        self.seatCount = seatCount
        self.guestCount = guestCount
        self.roundsPlayed = roundsPlayed
        self.isStarted = isStarted
        self.seated = seated
        self.hub = hub
        self.hubSeatOrder = hubSeatOrder
    }

    // MARK: TXT record

    private enum Key {
        static let version = "v", game = "t", word = "w", hostName = "h", hostHandle = "hh"
        static let hostAvatar = "ha", seats = "n", guests = "g", rounds = "r", started = "st", finished = "f", hub = "hub", hubOrder = "ho"
        static func seated(_ index: Int) -> String { "s\(index)" }
    }

    /// The TXT record as key/value strings (each value ≤ 255 bytes).
    var txtDictionary: [String: String] {
        var txt: [String: String] = [
            Key.version: String(Self.version),
            Key.game: game.uuidString,
            Key.word: String(tableWord.prefix(40)),
            Key.hostName: String(hostName.prefix(40)),
            Key.seats: String(seatCount),
            Key.guests: String(guestCount),
            Key.rounds: String(roundsPlayed),
            Key.started: isStarted ? "1" : "0",
            Key.finished: isFinished ? "1" : "0",
            Key.hub: hub.uuidString,
        ]
        // The host's player ID is not advertised (`hp` is no longer written): it let anyone nearby
        // claim to be the host. Discovery recognizes the host by handle instead.
        txt[Key.hostHandle] = hostHandle?.rawValue
        txt[Key.hubOrder] = hubSeatOrder.map(String.init)
        if let hostAvatar, let data = try? KedroJSON.encoder().encode(hostAvatar), data.count <= 200 {
            txt[Key.hostAvatar] = String(data: data, encoding: .utf8)
        }
        for (index, player) in seated.prefix(Self.maxSeatedListed).enumerated() {
            let name = player.displayName.replacingOccurrences(of: "|", with: " ").prefix(30)
            txt[Key.seated(index)] = [player.id.uuidString, String(name), player.handle?.rawValue ?? ""].joined(separator: "|")
        }
        return txt
    }

    var txtRecord: NWTXTRecord { NWTXTRecord(txtDictionary) }

    /// Parses a TXT record. nil for anything that isn't a compatible Kedro table.
    init?(txt: [String: String]) {
        guard
            txt[Key.version].flatMap(Int.init) == Self.version,
            let game = txt[Key.game].flatMap(GameID.init(uuidString:)),
            let hub = txt[Key.hub].flatMap(DeviceID.init(uuidString:)),
            let word = txt[Key.word], let hostName = txt[Key.hostName]
        else { return nil }
        self.game = game
        self.hub = hub
        tableWord = word
        self.hostName = hostName
        hostPlayer = nil // never advertised (see `txtDictionary`); `hp` from older builds is ignored
        hostHandle = txt[Key.hostHandle].flatMap(Handle.init)
        hostAvatar = txt[Key.hostAvatar].flatMap { try? KedroJSON.decoder().decode(Avatar.self, from: Data($0.utf8)) }
        seatCount = txt[Key.seats].flatMap(Int.init) ?? 0
        guestCount = txt[Key.guests].flatMap(Int.init) ?? 0
        roundsPlayed = txt[Key.rounds].flatMap(Int.init) ?? 0
        isStarted = txt[Key.started] == "1"
        isFinished = txt[Key.finished] == "1"
        hubSeatOrder = txt[Key.hubOrder].flatMap(Int.init)
        seated = (0..<Self.maxSeatedListed).compactMap { index in
            guard let value = txt[Key.seated(index)] else { return nil }
            let parts = value.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, let id = PlayerID(uuidString: parts[0]) else { return nil }
            return SeatedPlayer(id: id, displayName: parts[1], handle: Handle(parts[2]))
        }
    }

    init?(txtRecord: NWTXTRecord) {
        self.init(txt: txtRecord.dictionary)
    }
}

/// A table seen on the network, with the route to reach its hub.
nonisolated struct DiscoveredTable: Hashable, Sendable, Identifiable {
    nonisolated enum Source: Hashable, Sendable { case bonjour, multipeer }

    /// The browser's endpoint ID (stable while the table is visible).
    var id: String
    var advertisement: TableAdvertisement
    var source: Source
}
