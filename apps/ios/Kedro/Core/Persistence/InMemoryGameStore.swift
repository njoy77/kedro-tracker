import Foundation

/// A `GameStore` that keeps everything in memory. For previews and tests.
final class InMemoryGameStore: GameStore {
    private var operationsByGame: [GameID: [GameOperation]] = [:]
    private var knownOpIDs = Set<UUID>()
    private let broadcaster = OperationBroadcaster()

    init(operations: [GameOperation] = []) {
        for operation in operations where knownOpIDs.insert(operation.opId).inserted {
            operationsByGame[operation.gameId, default: []].append(operation)
        }
    }

    @discardableResult
    func append(_ operations: [GameOperation]) async throws -> [GameOperation] {
        let new = operations.filter { knownOpIDs.insert($0.opId).inserted }
        for operation in new {
            operationsByGame[operation.gameId, default: []].append(operation)
        }
        if !new.isEmpty { broadcaster.publish(new) }
        return new
    }

    func operations(for game: GameID) async throws -> [GameOperation] {
        (operationsByGame[game] ?? []).sorted(by: GameOperation.foldOrder)
    }

    func updates(for game: GameID) -> AsyncStream<[GameOperation]> {
        broadcaster.stream(for: game)
    }

    func gameUpdates() -> AsyncStream<GameID> {
        broadcaster.anyStream()
    }

    func games() async throws -> [GameSummary] {
        operationsByGame.map { GameSummary(state: GameState.fold($0.value, gameID: $0.key)) }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    func gameState(_ game: GameID) async throws -> GameState? {
        guard let operations = operationsByGame[game], !operations.isEmpty else { return nil }
        return GameState.fold(operations, gameID: game)
    }

    func finishedGames() async throws -> [GameState] {
        operationsByGame
            .map { GameState.fold($0.value, gameID: $0.key) }
            .filter { $0.status == .finished }
            .sorted { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
    }
}
