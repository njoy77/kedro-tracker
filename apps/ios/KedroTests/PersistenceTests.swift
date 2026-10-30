import Foundation
import Testing
@testable import Kedro

@Suite("Game stores")
struct PersistenceTests {
    static func makeStores() throws -> [any GameStore] {
        [InMemoryGameStore(), SwiftDataGameStore(container: try KedroPersistence.makeContainer(inMemory: true))]
    }

    @Test("Append is idempotent by opId", arguments: [0, 1])
    func idempotent(storeIndex: Int) async throws {
        let store = try Self.makeStores()[storeIndex]
        let operations = PreviewData.sampleOperations()
        let first = try await store.append(operations)
        #expect(first.count == operations.count)
        let second = try await store.append(operations)
        #expect(second.isEmpty)
        let stored = try await store.operations(for: PreviewData.sampleGameID)
        #expect(stored.count == operations.count)
        #expect(stored == operations.sorted(by: GameOperation.foldOrder))
    }

    @Test("Games, states and finished games", arguments: [0, 1])
    func queries(storeIndex: Int) async throws {
        let store = try Self.makeStores()[storeIndex]
        try await DemoDataSeeder.seed(into: store)
        let games = try await store.games()
        #expect(games.count == 42)
        let finished = try await store.finishedGames()
        #expect(finished.count == 41) // abandoned excluded
        #expect(finished.allSatisfy { $0.status == .finished })
        #expect(finished.map { $0.finishedAt ?? .distantPast } == finished.map { $0.finishedAt ?? .distantPast }.sorted())
        let sample = try #require(try await store.gameState(PreviewData.sampleGameID))
        #expect(sample.standings.map(\.total) == [28, 34, 65, 67, 70])
        #expect(try await store.gameState(GameID()) == nil)
        #expect(try await DemoDataSeeder.seed(into: store) == 0)
    }

    @Test("Updates stream only new operations", arguments: [0, 1])
    func updates(storeIndex: Int) async throws {
        let store = try Self.makeStores()[storeIndex]
        let operations = PreviewData.sampleOperations(throughRound: 2, finished: false)
        let stream = store.updates(for: PreviewData.sampleGameID)
        try await store.append(operations)
        try await store.append(operations) // duplicates: no batch
        let more = PreviewData.sampleOperations(throughRound: 3, finished: false).filter { op in !operations.contains { $0.opId == op.opId } }
        try await store.append(more)
        var iterator = stream.makeAsyncIterator()
        let firstBatch = await iterator.next()
        let secondBatch = await iterator.next()
        #expect(firstBatch?.count == operations.count)
        #expect(secondBatch == more)
    }

    @Test("Local directory: played-with and guest suggestions")
    func directory() async throws {
        let store = InMemoryGameStore(operations: PreviewData.historyOperations)
        let directory = LocalPlayerDirectory(store: store) { PreviewData.noah.ref }
        let playedWith = try await directory.playedWith()
        #expect(!playedWith.isEmpty)
        #expect(!playedWith.contains { $0.player.id == PreviewData.noah.id })
        #expect(try await directory.search("pri").map(\.displayName) == ["Priya"])
        #expect(try await directory.search("@max").map(\.displayName) == ["Max"])
        let sam = try await directory.guestSuggestions(matching: "sa")
        #expect(sam.first?.name == "Sam")
        #expect(sam.first?.gamesTogether == 2)
    }

    @Test("Profile store keeps the profile across loads")
    func profile() throws {
        let container = try KedroPersistence.makeContainer(inMemory: true)
        let store = ProfileStore(container: container)
        #expect(store.profile == nil)
        store.save(PreviewData.noahProfile)
        #expect(ProfileStore(container: container).profile == PreviewData.noahProfile)
        store.clear()
        #expect(ProfileStore(container: container).profile == nil)
    }
}

@Suite("Preferences")
struct PreferencesTests {
    private func defaults() -> UserDefaults {
        let name = "kedro.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name) ?? .standard
    }

    @Test("Defaults: Unhinged, sounds off, custom taunts on")
    func defaultsAreRight() {
        let preferences = AppPreferences(defaults: defaults())
        #expect(preferences.languageLevel == .unhinged)
        #expect(preferences.sounds.isEnabled == false)
        #expect(preferences.sounds.plays(.winner) == false)
        #expect(preferences.customTauntsEnabled)
        #expect(preferences.lastPlannedRounds == 6)
    }

    @Test("Under 18 locks Clean and turns custom taunts off")
    func under18() {
        let preferences = AppPreferences(defaults: defaults())
        preferences.isUnder18 = true
        #expect(preferences.effectiveLanguageLevel == .clean)
        #expect(preferences.effectiveCustomTaunts == false)
    }

    @Test("Values persist")
    func persistence() {
        let store = defaults()
        let preferences = AppPreferences(defaults: store)
        preferences.languageLevel = .spicy
        preferences.sounds.isEnabled = true
        preferences.sounds.set(.deadLast, on: false)
        let reloaded = AppPreferences(defaults: store)
        #expect(reloaded.languageLevel == .spicy)
        #expect(reloaded.sounds.plays(.winner))
        #expect(!reloaded.sounds.plays(.deadLast))
        #expect(reloaded.showsLearnerHints(gamesPlayed: 2))
        #expect(!reloaded.showsLearnerHints(gamesPlayed: 3))
    }
}
