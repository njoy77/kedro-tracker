import Foundation
import Observation

/// Moves operations between phones and the backend (design §5.2, §11). The Networking agent
/// implements the real one (peer-to-peer `TableLink` plus Supabase sync, in Core/TableLink and
/// Core/Sync); `LocalOnlyTransport` is the offline stand-in.
///
/// Contract:
/// - `send` is fire-and-forget from the caller's point of view: operations are already in the
///   `GameStore` before they're sent, and the transport retries on its own.
/// - `incoming(for:)` yields operations from other devices (possibly duplicates, possibly ones
///   this phone sent). `GameSession` appends them to the `GameStore`, which de-duplicates.
/// - `syncState` drives the sync pill, which appears only when `isUnusual` (design §11).
protocol OperationTransport: AnyObject, Sendable {
    var syncState: SyncState { get }

    /// Starts exchanging operations for a game (join the table's link, subscribe to Realtime).
    func connect(to game: GameID) async

    /// Stops exchanging operations for a game.
    func disconnect(from game: GameID) async

    /// Sends local operations to peers and the backend.
    func send(_ operations: [GameOperation]) async

    /// Operations arriving from elsewhere for a game.
    func incoming(for game: GameID) -> AsyncStream<[GameOperation]>
}

/// Connection state, shown as a word in a pill (never a color; design §3.3).
nonisolated enum SyncState: Hashable, Sendable {
    /// Online and in sync. No pill.
    case online
    /// Catching up with the backend. "Syncing…" (F-03)
    case syncing
    /// No internet, but `peers` other phones are in sync directly. "Offline · 5 phones in sync" (F-01)
    case offlinePeers(Int)
    /// No internet and no peers. "Offline · saved on this phone" (F-02)
    case offlineSolo

    /// Show the pill only for unusual states.
    var isUnusual: Bool { self != .online }

    /// The copy deck ID for the pill text (render with `Voice`).
    var copyID: String? {
        switch self {
        case .online: nil
        case .syncing: "F-03"
        case .offlinePeers: "F-01"
        case .offlineSolo: "F-02"
        }
    }

    /// The phone count for F-01, counting this phone.
    var phoneCount: Int? {
        if case .offlinePeers(let peers) = self { peers + 1 } else { nil }
    }
}

/// A transport that talks to nobody: every operation stays on this phone. Used until the
/// Networking agent's transport is wired in, and in previews and tests.
@Observable
final class LocalOnlyTransport: OperationTransport {
    private(set) var syncState: SyncState
    /// Every operation passed to `send`, for tests.
    private(set) var sent: [GameOperation] = []
    @ObservationIgnored private var continuations: [GameID: [UUID: AsyncStream<[GameOperation]>.Continuation]] = [:]

    init(syncState: SyncState = .offlineSolo) {
        self.syncState = syncState
    }

    func connect(to game: GameID) async {}

    func disconnect(from game: GameID) async {}

    func send(_ operations: [GameOperation]) async {
        sent.append(contentsOf: operations)
    }

    func incoming(for game: GameID) -> AsyncStream<[GameOperation]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [GameOperation].self)
        let token = UUID()
        continuations[game, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[game]?[token] = nil }
        }
        return stream
    }

    /// Simulates operations arriving from another phone (tests and previews).
    func deliver(_ operations: [GameOperation]) {
        for (game, batch) in Dictionary(grouping: operations, by: \.gameId) {
            for continuation in (continuations[game] ?? [:]).values {
                continuation.yield(batch)
            }
        }
    }
}
