import Foundation
import Observation

/// Did the Reading (design §12.6): the Learn feature sets this `UserDefaults` flag once the
/// lessons and the Score a Round drill are done (`@AppStorage(LearningProgress.didTheReadingKey)`).
nonisolated enum LearningProgress {
    static let didTheReadingKey = "kedro.learn.didTheReading"

    static func didTheReading(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: didTheReadingKey)
    }
}

/// Keeps a `StatsSnapshot` of the store's finished games, rebuilt (off the main actor) whenever
/// games change. There is one model per store, so every stats screen shows the same numbers and
/// a pushed screen never starts empty:
///
/// ```swift
/// @Environment(AppModel.self) private var app
/// private var stats: StatsModel { .shared(for: app.store) }
/// …
/// .task { await stats.follow(app.store, viewer: app.profile?.identity) }
/// ```
///
/// Also the Play tab's `StakesProvider` (Tonight's stakes, Since you last looked, the Wrapped
/// slot, the rank meter).
@Observable
final class StatsModel: StakesProvider {
    private(set) var snapshot: StatsSnapshot
    private(set) var isLoaded: Bool
    /// Claims and blocks to apply. Setting them takes effect on the next load.
    var options: StatsOptions

    @ObservationIgnored private var pendingReload: Task<Void, Never>?
    @ObservationIgnored private var lastLoad: Date?

    init(snapshot: StatsSnapshot? = nil, options: StatsOptions = StatsOptions()) {
        self.snapshot = snapshot ?? .empty
        isLoaded = snapshot != nil
        self.options = options
        if snapshot != nil { lastLoad = .now }
    }

    // MARK: Shared instances

    private static var instances: [ObjectIdentifier: StatsModel] = [:]

    /// The model for a store (created on first use).
    static func shared(for store: any GameStore) -> StatsModel {
        let key = ObjectIdentifier(store)
        if let model = instances[key] { return model }
        let model = StatsModel()
        instances[key] = model
        return model
    }

    // MARK: Loading

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
        lastLoad = .now
    }

    /// Loads (unless another screen just did), then reloads whenever games change, until the
    /// task is cancelled. Several screens may follow at once; their reloads are coalesced.
    func follow(_ store: any GameStore, viewer: PlayerRef? = nil) async {
        if !isLoaded || (lastLoad.map { Date.now.timeIntervalSince($0) > 2 } ?? true) {
            await load(from: store, viewer: viewer)
        }
        for await _ in store.gameUpdates() {
            pendingReload?.cancel()
            pendingReload = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await self?.load(from: store, viewer: viewer)
            }
        }
    }

    // MARK: StakesProvider

    func tonightsStakes(for me: PlayerRef, table: [PlayerRef], voice: Voice) -> TonightStakes {
        snapshot.tonightsStakes(for: me, table: table, voice: voice)
    }

    func sinceYouLastLooked(for me: PlayerRef, since: Date?, voice: Voice) -> [SinceYouLastLookedItem] {
        snapshot.sinceYouLastLooked(for: me, since: since, voice: voice)
    }

    func wrappedSlot(for me: PlayerRef, voice: Voice, now: Date) -> WrappedSlot? {
        snapshot.wrappedSlot(for: me, voice: voice, now: now)
    }

    func progress(for me: PlayerRef) -> PlayerProgress {
        snapshot.progress(for: me)
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
