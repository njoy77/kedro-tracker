import Foundation
import Observation
import OSLog

/// The real `OperationTransport`: the peer-to-peer `TableLink` for the phones at the table plus
/// `BackendSync` for the backend, which is "just another peer" (design §5.2).
///
/// - `send` goes to both: the link relays to the table, the queue uploads when it can.
/// - Operations from the link are queued for upload (a phone with internet relays for the table),
///   and operations from the backend are broadcast on the link (so a phone without internet still
///   hears about a late reaction or a server retraction).
/// - Only live games (lobby or active, or not stored yet, as when opened from an invite) join the
///   link. Finished games still follow the backend for late reactions and receipts.
/// - `syncState` drives the pill: online and caught up → no pill; catching up → "Syncing…";
///   no internet → "Offline · n phones in sync" or "Offline · saved on this phone".
@Observable
final class NetworkedTransport: OperationTransport {
    let link: TableLink
    let sync: BackendSync

    @ObservationIgnored private let store: any GameStore
    @ObservationIgnored private let path: any NetworkPathMonitoring
    @ObservationIgnored private let identity: () -> LocalIdentity
    @ObservationIgnored private let clock: HybridLogicalClock
    @ObservationIgnored private var connections: [GameID: Int] = [:]
    @ObservationIgnored private var bridges: [GameID: Task<Void, Never>] = [:]
    @ObservationIgnored private var continuations: [GameID: [UUID: AsyncStream<[GameOperation]>.Continuation]] = [:]
    @ObservationIgnored private var pathTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "Sync")

    init(
        store: any GameStore,
        link: TableLink,
        sync: BackendSync,
        path: any NetworkPathMonitoring,
        identity: @escaping () -> LocalIdentity,
        clock: HybridLogicalClock
    ) {
        self.store = store
        self.link = link
        self.sync = sync
        self.path = path
        self.identity = identity
        self.clock = clock
        sync.onRefused = { [weak self] refused in self?.retractRefusedTaunts(refused) }
        pathTask = Task { [weak self, path] in
            for await online in path.changes() where online {
                await self?.sync.reachabilityChanged()
            }
        }
    }

    isolated deinit {
        pathTask?.cancel()
        for bridge in bridges.values { bridge.cancel() }
    }

    // MARK: OperationTransport

    var syncState: SyncState {
        if path.isOnline {
            if sync.isCatchingUp { return .syncing }
            return .online
        }
        let peers = link.connectedPeerCount
        return peers > 0 ? .offlinePeers(peers) : .offlineSolo
    }

    func connect(to game: GameID) async {
        connections[game, default: 0] += 1
        guard connections[game] == 1 else { return }
        let state = try? await store.gameState(game)
        if state?.status.isLive ?? true {
            link.join(game)
        }
        sync.connect(to: game)
        bridges[game] = Task { [weak self] in await self?.bridge(game) }
    }

    func disconnect(from game: GameID) async {
        guard let count = connections[game] else { return }
        if count > 1 {
            connections[game] = count - 1
            return
        }
        connections[game] = nil
        bridges.removeValue(forKey: game)?.cancel()
        sync.disconnect(from: game)
        if link.game == game { link.leave() }
    }

    func send(_ operations: [GameOperation]) async {
        guard !operations.isEmpty else { return }
        link.broadcast(operations)
        sync.enqueue(operations)
    }

    func incoming(for game: GameID) -> AsyncStream<[GameOperation]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [GameOperation].self, bufferingPolicy: .unbounded)
        let token = UUID()
        continuations[game, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[game]?[token] = nil }
        }
        return stream
    }

    // MARK: Bridging

    /// Forwards both sources to `incoming` and across to each other while the game is connected.
    private func bridge(_ game: GameID) async {
        let fromLink = link.incoming(for: game)
        let fromBackend = sync.incoming(for: game)
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await batch in fromLink {
                    await self.deliver(batch, game: game)
                    await self.sync.enqueue(batch)
                }
            }
            group.addTask {
                for await batch in fromBackend {
                    await self.deliver(batch, game: game)
                    await self.link.broadcast(batch)
                }
            }
        }
    }

    private func deliver(_ batch: [GameOperation], game: GameID) {
        for continuation in (continuations[game] ?? [:]).values {
            continuation.yield(batch)
        }
    }

    // MARK: Retractions

    /// A custom taunt this phone sent that the server refused failed the server check: retract it
    /// from every phone at the table (design §11). The server's own retraction, if it makes one,
    /// arrives later and is harmless (retracting twice hides the same taunt).
    private func retractRefusedTaunts(_ refused: [GameOperation]) {
        let me = identity()
        let retractions = refused.compactMap { operation -> GameOperation? in
            guard operation.deviceId == me.deviceID,
                  case .tauntSent(let taunt) = operation.payload, taunt.content.isCustom else { return nil }
            return GameOperation(
                gameId: operation.gameId,
                deviceId: me.deviceID,
                hlc: clock.tick(),
                actorPlayerId: me.actorPlayerID,
                payload: .tauntRetracted(.init(tauntId: taunt.tauntId, reason: "server"))
            )
        }
        guard !retractions.isEmpty else { return }
        log.notice("Retracting \(retractions.count) taunt(s) the server refused")
        Task {
            do {
                try await store.append(retractions)
            } catch {
                log.error("Couldn't store retractions: \(error.localizedDescription, privacy: .public)")
            }
            for (game, batch) in Dictionary(grouping: retractions, by: \.gameId) {
                deliver(batch, game: game)
            }
            await send(retractions)
        }
    }
}
