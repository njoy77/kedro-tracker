import Foundation
import OSLog
import SwiftData

/// The app's `GameStore`: operations in SwiftData, folded states cached per game.
final class SwiftDataGameStore: GameStore {
    /// Kept alive here: a `ModelContext` doesn't retain its container.
    private let container: ModelContainer
    private let context: ModelContext
    private let broadcaster = OperationBroadcaster()
    private var stateCache: [GameID: GameState] = [:]
    private let encoder = KedroJSON.encoder()
    private let decoder = KedroJSON.decoder()
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "GameStore")

    init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    @discardableResult
    func append(_ operations: [GameOperation]) async throws -> [GameOperation] {
        guard !operations.isEmpty else { return [] }
        let ids = operations.map(\.opId)
        let existing = try context.fetch(FetchDescriptor<StoredOperation>(predicate: #Predicate { ids.contains($0.opId) }))
        var known = Set(existing.map(\.opId))
        var new: [GameOperation] = []
        for operation in operations where known.insert(operation.opId).inserted {
            context.insert(StoredOperation(
                opId: operation.opId,
                gameId: operation.gameId.rawValue,
                hlc: operation.hlc.stringValue,
                deviceId: operation.deviceId.rawValue,
                type: operation.type.rawValue,
                payload: try encoder.encode(operation)
            ))
            new.append(operation)
        }
        guard !new.isEmpty else { return [] }
        try context.save()
        for game in Set(new.map(\.gameId)) { stateCache[game] = nil }
        broadcaster.publish(new)
        return new
    }

    func operations(for game: GameID) async throws -> [GameOperation] {
        let id = game.rawValue
        let stored = try context.fetch(FetchDescriptor<StoredOperation>(predicate: #Predicate { $0.gameId == id }))
        return decode(stored).sorted(by: GameOperation.foldOrder)
    }

    func updates(for game: GameID) -> AsyncStream<[GameOperation]> {
        broadcaster.stream(for: game)
    }

    func gameUpdates() -> AsyncStream<GameID> {
        broadcaster.anyStream()
    }

    func games() async throws -> [GameSummary] {
        try allStates().map(GameSummary.init(state:))
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    func gameState(_ game: GameID) async throws -> GameState? {
        if let cached = stateCache[game] { return cached }
        let operations = try await operations(for: game)
        guard !operations.isEmpty else { return nil }
        let state = GameState.fold(operations, gameID: game)
        stateCache[game] = state
        return state
    }

    func finishedGames() async throws -> [GameState] {
        try allStates()
            .filter { $0.status == .finished }
            .sorted { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
    }

    // MARK: Private

    private func allStates() throws -> [GameState] {
        var descriptor = FetchDescriptor<StoredOperation>()
        descriptor.propertiesToFetch = [\.gameId]
        let gameIDs = Set(try context.fetch(descriptor).map(\.gameId)).map(GameID.init)
        return try gameIDs.map { game in
            if let cached = stateCache[game] { return cached }
            let id = game.rawValue
            let stored = try context.fetch(FetchDescriptor<StoredOperation>(predicate: #Predicate { $0.gameId == id }))
            let state = GameState.fold(decode(stored), gameID: game)
            stateCache[game] = state
            return state
        }
    }

    private func decode(_ stored: [StoredOperation]) -> [GameOperation] {
        stored.compactMap { row in
            do {
                return try decoder.decode(GameOperation.self, from: row.payload)
            } catch {
                log.error("Skipping undecodable operation \(row.opId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }
}
