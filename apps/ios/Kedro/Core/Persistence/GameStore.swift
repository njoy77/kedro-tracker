import Foundation

/// Where operation logs live on this phone. The single local source of truth: everything that
/// receives operations (the local `GameSession`, the peer-to-peer link, the backend sync) writes
/// them here with `append`, and everything that shows a game reads from here.
///
/// Implementations: `SwiftDataGameStore` (the app), `InMemoryGameStore` (previews and tests).
/// Main-actor isolated, like the rest of the app's models.
protocol GameStore: AnyObject, Sendable {
    /// Stores operations, ignoring any whose `opId` is already stored (idempotent).
    /// - Returns: the operations that were new, in the order given.
    @discardableResult
    func append(_ operations: [GameOperation]) async throws -> [GameOperation]

    /// Every stored operation for a game, in fold order.
    func operations(for game: GameID) async throws -> [GameOperation]

    /// Newly appended operations for a game, as they're stored. Each batch contains only new
    /// operations. The stream ends when the consumer's task is cancelled.
    func updates(for game: GameID) -> AsyncStream<[GameOperation]>

    /// The ID of every game that gets new operations, as it happens (for lists such as Recent).
    func gameUpdates() -> AsyncStream<GameID>

    /// Summaries of every game on this phone, newest activity first (including abandoned).
    func games() async throws -> [GameSummary]

    /// The full state of one game, or nil if nothing is stored for it.
    func gameState(_ game: GameID) async throws -> GameState?

    /// Finished, non-abandoned games (early-ended included), oldest first. The input to every
    /// stat, leaderboard and badge (design §12: derived, never stored).
    func finishedGames() async throws -> [GameState]
}

extension GameStore {
    @discardableResult
    func append(_ operation: GameOperation) async throws -> GameOperation? {
        try await append([operation]).first
    }

    /// The newest lobby or active game, for resuming after a relaunch.
    func liveGames() async throws -> [GameSummary] {
        try await games().filter { $0.status.isLive }
    }
}

/// A game in a list (Recent, history).
nonisolated struct GameSummary: Hashable, Sendable, Identifiable {
    var id: GameID
    var tableWord: String
    var status: GameStatus
    var finishReason: FinishReason?
    var seats: [Seat]
    /// Best first.
    var standings: [Standing]
    var roundsPlayed: Int
    var plannedRounds: Int
    var createdAt: Date?
    var finishedAt: Date?
    /// The newest operation's time.
    var updatedAt: Date?

    init(state: GameState) {
        id = state.gameID
        tableWord = state.config.tableWord
        status = state.status
        finishReason = state.finishReason
        seats = state.seats
        standings = state.standings
        roundsPlayed = state.rounds.count
        plannedRounds = state.config.plannedRounds
        createdAt = state.createdAt
        finishedAt = state.finishedAt
        updatedAt = state.latestHLC?.date
    }

    var winners: [SeatID] { status == .finished ? standings.filter(\.isLeader).map(\.id) : [] }
}

/// Fans out appended operations to `updates(for:)` / `gameUpdates()` subscribers. Shared by the
/// store implementations.
final class OperationBroadcaster {
    private var gameContinuations: [GameID: [UUID: AsyncStream<[GameOperation]>.Continuation]] = [:]
    private var anyContinuations: [UUID: AsyncStream<GameID>.Continuation] = [:]

    func stream(for game: GameID) -> AsyncStream<[GameOperation]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [GameOperation].self, bufferingPolicy: .unbounded)
        let token = UUID()
        gameContinuations[game, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.gameContinuations[game]?[token] = nil }
        }
        return stream
    }

    func anyStream() -> AsyncStream<GameID> {
        let (stream, continuation) = AsyncStream.makeStream(of: GameID.self, bufferingPolicy: .bufferingNewest(32))
        let token = UUID()
        anyContinuations[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.anyContinuations[token] = nil }
        }
        return stream
    }

    func publish(_ operations: [GameOperation]) {
        let byGame = Dictionary(grouping: operations, by: \.gameId)
        for (game, batch) in byGame {
            for continuation in (gameContinuations[game] ?? [:]).values {
                continuation.yield(batch)
            }
            for continuation in anyContinuations.values {
                continuation.yield(game)
            }
        }
    }
}
