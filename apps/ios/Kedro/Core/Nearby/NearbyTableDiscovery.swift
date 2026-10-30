import Foundation
import Observation
import OSLog

/// The real `TableDiscovery` (design §5.2–§5.4): browses Bonjour for `_kedro-table._tcp`, turns
/// TXT records into Table cards, ranges each table's hub with Nearby Interaction for "At your
/// table", and advertises this phone's table through the `TableLink` (plus the Bluetooth nearby
/// alert beacon while seated).
///
/// Ordering: closest first when distances are known; otherwise most played-with overlap, then
/// the table word (so the same list reads the same on every phone).
final class NearbyTableDiscovery: TableDiscovery {
    private let link: TableLink
    private let networking: any TableLinkNetworking
    private let directory: any PlayerDirectory
    private let identity: () -> LocalIdentity
    private let ranger: NearbyRanger?
    private let alerts: NearbyAlertService?
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Nearby")

    init(
        link: TableLink,
        networking: any TableLinkNetworking,
        directory: any PlayerDirectory,
        identity: @escaping () -> LocalIdentity,
        ranger: NearbyRanger? = NearbyRanger.isSupported ? NearbyRanger() : nil,
        alerts: NearbyAlertService? = nil
    ) {
        self.link = link
        self.networking = networking
        self.directory = directory
        self.identity = identity
        self.ranger = ranger
        self.alerts = alerts
    }

    // MARK: TableDiscovery

    func nearbyTables() -> AsyncStream<[NearbyTable]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [NearbyTable].self, bufferingPolicy: .bufferingNewest(1))
        let task = Task { [weak self] in
            await self?.discover(into: continuation)
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func advertise(_ table: AdvertisedTable) async {
        link.advertise(table)
        alerts?.startBeacon(for: identity().player, game: table.gameID)
    }

    func stopAdvertising() async {
        link.stopAdvertising()
        alerts?.stopBeacon()
    }

    // MARK: Discovery

    private func discover(into continuation: AsyncStream<[NearbyTable]>.Continuation) async {
        let playedWith = Dictionary(((try? await directory.playedWith()) ?? []).map { ($0.player.id, $0) }) { first, _ in first }
        let visible = VisibleTables()
        var peeks: [GameID: Task<Void, Never>] = [:]

        // Re-emit when a distance changes.
        let distances = ranger.map { ranger in
            Task { [weak self] in
                for await _ in Observations({ ranger.distances }) {
                    guard let self else { return }
                    continuation.yield(cards(from: visible.tables, playedWith: playedWith))
                }
            }
        }
        defer {
            distances?.cancel()
            for (game, peek) in peeks {
                peek.cancel()
                ranger?.endSession(for: Self.peerKey(game))
            }
        }

        for await tables in networking.browse() {
            visible.tables = tables
            let games = Set(tables.map(\.advertisement.game))
            for (game, peek) in peeks where !games.contains(game) {
                peek.cancel()
                peeks[game] = nil
                ranger?.endSession(for: Self.peerKey(game))
            }
            if ranger != nil {
                for table in tables where peeks[table.advertisement.game] == nil && table.advertisement.game != link.game {
                    peeks[table.advertisement.game] = Task { [weak self] in await self?.peek(table) }
                }
            }
            continuation.yield(cards(from: tables, playedWith: playedWith))
        }
    }

    /// The tables a discovery run currently sees (shared with its distance observer).
    private final class VisibleTables {
        var tables: [DiscoveredTable] = []
    }

    /// Builds the Table cards: one per game, excluding finished tables and the one we're at.
    func cards(from tables: [DiscoveredTable], playedWith: [PlayerID: PlayedWith]) -> [NearbyTable] {
        var best: [GameID: TableAdvertisement] = [:]
        for table in tables {
            let ad = table.advertisement
            guard !ad.isFinished, ad.game != link.game else { continue }
            if let current = best[ad.game], current.hubRank < ad.hubRank { continue }
            best[ad.game] = ad
        }
        let cards = best.values.map { ad in
            NearbyTable(
                id: ad.game,
                host: hostSummary(ad, playedWith: playedWith),
                tableWord: ad.tableWord,
                distance: ranger?.distance(to: Self.peerKey(ad.game)),
                seatedPlayers: ad.seated.map { seated in
                    playedWith[seated.id]?.player ?? PlayerSummary(
                        id: seated.id, displayName: seated.displayName,
                        handle: seated.handle ?? Handle(constant: "player"), avatar: .curated(.spade)
                    )
                },
                guestCount: ad.guestCount,
                isPlayedWith: ad.hostPlayer.map { playedWith[$0] != nil } ?? false,
                roundsPlayed: ad.roundsPlayed
            )
        }
        return Self.ordered(cards, playedWith: Set(playedWith.keys))
    }

    static func ordered(_ cards: [NearbyTable], playedWith: Set<PlayerID>) -> [NearbyTable] {
        func overlap(_ card: NearbyTable) -> Int {
            card.seatedPlayers.filter { playedWith.contains($0.id) }.count + (card.isPlayedWith ? 1 : 0)
        }
        return cards.sorted { lhs, rhs in
            switch (lhs.distance, rhs.distance) {
            case let (left?, right?) where left != right: return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            let (left, right) = (overlap(lhs), overlap(rhs))
            if left != right { return left > right }
            return (lhs.tableWord, lhs.id.uuidString) < (rhs.tableWord, rhs.id.uuidString)
        }
    }

    private func hostSummary(_ ad: TableAdvertisement, playedWith: [PlayerID: PlayedWith]) -> PlayerSummary {
        if let host = ad.hostPlayer, let known = playedWith[host] { return known.player }
        // A guest-mode host has no player ID; the hub's device ID stands in so the card has an identity.
        return PlayerSummary(
            id: ad.hostPlayer ?? PlayerID(ad.hub.rawValue),
            displayName: ad.hostName,
            handle: ad.hostHandle ?? Handle(constant: "guest"),
            avatar: ad.hostAvatar ?? .curated(.spade)
        )
    }

    static func peerKey(_ game: GameID) -> String { "peek:" + game.uuidString }

    /// Opens a look-only connection to a table's hub to swap Nearby Interaction tokens.
    private func peek(_ table: DiscoveredTable) async {
        guard let ranger else { return }
        let key = Self.peerKey(table.advertisement.game)
        guard let token = ranger.localToken(for: key) else { return }
        do {
            let channel = try await networking.connect(to: table)
            defer { channel.close() }
            let me = identity()
            try await channel.send(.hello(LinkHello(purpose: .peek, game: table.advertisement.game, device: me.deviceID, person: me.player, displayName: me.displayName)))
            try await channel.send(.nearbyToken(token))
            for try await message in channel.messages {
                switch message {
                case .nearbyToken(let theirs): ranger.didReceive(theirs, from: key)
                case .ping(let nonce): try await channel.send(.pong(nonce))
                case .refused, .goodbye: return
                default: break
                }
            }
        } catch {
            log.info("Peek ended: \(error.localizedDescription, privacy: .public)")
        }
    }
}
