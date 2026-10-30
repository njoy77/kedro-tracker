import Foundation
import Observation

/// The App Clip's `OperationTransport`: polls the backend for new operations and posts its own.
///
/// The clip can't join the table's peer-to-peer link, so the backend is its only peer (design
/// §5.8). Polling every few seconds is plenty for watching scores and reporting a hand; the full
/// app gets Realtime. Unsent operations are kept and retried on the next poll, so a dropped
/// connection loses nothing (`GameSession` already stored them in its `GameStore`).
@Observable
final class ClipTransport: OperationTransport {
    static let pollInterval: Duration = .seconds(3)

    private(set) var syncState: SyncState = .syncing

    @ObservationIgnored private let api: ClipAPI
    @ObservationIgnored private let accessToken: String
    @ObservationIgnored private var latest: HLC?
    @ObservationIgnored private var unsent: [GameOperation] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var continuations: [UUID: AsyncStream<[GameOperation]>.Continuation] = [:]

    init(api: ClipAPI, accessToken: String, latest: HLC?) {
        self.api = api
        self.accessToken = accessToken
        self.latest = latest
    }

    func connect(to game: GameID) async {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll(game)
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func disconnect(from game: GameID) async {
        pollTask?.cancel()
        pollTask = nil
    }

    func send(_ operations: [GameOperation]) async {
        unsent.append(contentsOf: operations)
        await flush()
    }

    func incoming(for game: GameID) -> AsyncStream<[GameOperation]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [GameOperation].self)
        let token = UUID()
        continuations[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[token] = nil }
        }
        return stream
    }

    /// One round trip: send what's waiting, then fetch what's new.
    func poll(_ game: GameID) async {
        await flush()
        do {
            let operations = try await api.operations(gameID: game, after: latest, token: accessToken)
            syncState = unsent.isEmpty ? .online : .syncing
            guard !operations.isEmpty else { return }
            latest = operations.map(\.hlc).max().map { max($0, latest ?? $0) } ?? latest
            for continuation in continuations.values {
                continuation.yield(operations)
            }
        } catch {
            syncState = .offlineSolo
        }
    }

    private func flush() async {
        guard !unsent.isEmpty else { return }
        let batch = unsent
        do {
            _ = try await api.send(batch, token: accessToken)
            let sent = Set(batch.map(\.opId))
            unsent.removeAll { sent.contains($0.opId) }
            syncState = unsent.isEmpty ? .online : .syncing
        } catch {
            syncState = .offlineSolo
        }
    }
}
