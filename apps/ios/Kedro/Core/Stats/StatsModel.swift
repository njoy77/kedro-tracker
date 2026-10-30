import Foundation
import Observation

/// Did the Reading (design §12.6): the Learn feature sets this `UserDefaults` flag once the
/// lessons and the Score a Round drill are done (`@AppStorage(LearningProgress.didTheReadingKey)`).
enum LearningProgress {
    static let didTheReadingKey = "kedro.learn.didTheReading"

    static func didTheReading(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: didTheReadingKey)
    }
}

/// Keeps a `StatsSnapshot` of the store's finished games, rebuilt (off the main actor) whenever
/// games change. Screens own one with `@State` and run `follow(_:viewer:)` in `.task`:
///
/// ```swift
/// @State private var stats = StatsModel()
/// …
/// .task { await stats.follow(app.store, viewer: app.profile?.identity) }
/// ```
///
/// Also the Play tab's `StakesProvider` (Tonight's stakes, Since you last looked).
@Observable
final class StatsModel: StakesProvider {
    private(set) var snapshot: StatsSnapshot
    private(set) var isLoaded: Bool
    /// Claims and blocks to apply; changing them takes effect on the next load.
    var options: StatsOptions

    @ObservationIgnored private var pendingReload: Task<Void, Never>?

    init(snapshot: StatsSnapshot? = nil, options: StatsOptions = StatsOptions()) {
        self.snapshot = snapshot ?? .empty
        isLoaded = snapshot != nil
        self.options = options
    }

    /// Rebuilds from the store once.
    func load(from store: any GameStore, viewer: PlayerRef? = nil) async {
        var options = options
        if let viewer, LearningProgress.didTheReading() { options.didTheReading.insert(viewer) }
        guard let states = try? await store.finishedGames() else {
            isLoaded = true
            return
        }
        snapshot = await StatsSnapshot.buildInBackground(states, options: options)
        isLoaded = true
    }

    /// Loads, then reloads whenever games change (coalesced), until the task is cancelled.
    func follow(_ store: any GameStore, viewer: PlayerRef? = nil) async {
        await load(from: store, viewer: viewer)
        for await _ in store.gameUpdates() {
            pendingReload?.cancel()
            pendingReload = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await self?.load(from: store, viewer: viewer)
            }
        }
        pendingReload?.cancel()
    }

    // MARK: StakesProvider

    func tonightsStakes(for me: PlayerRef, table: [PlayerRef], voice: Voice) -> TonightStakes {
        snapshot.tonightsStakes(for: me, table: table, voice: voice)
    }

    func sinceYouLastLooked(for me: PlayerRef, since: Date?, voice: Voice) -> [SinceYouLastLookedItem] {
        snapshot.sinceYouLastLooked(for: me, since: since, voice: voice)
    }
}

extension StatsModel {
    /// The demo history plus the finished sample game (previews).
    static var preview: StatsModel {
        StatsModel(snapshot: .preview)
    }
}

extension StatsSnapshot {
    /// Sample history plus the finished §17 game.
    nonisolated static var preview: StatsSnapshot {
        let states = PreviewData.history.compactMap { operations in
            operations.first.map { GameState.fold(operations, gameID: $0.gameId) }
        } + [PreviewData.sampleState(throughRound: 8, finished: true)]
        return build(states)
    }
}
