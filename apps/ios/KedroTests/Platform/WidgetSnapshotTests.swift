import Foundation
import Testing
@testable import Kedro

/// The app-group snapshot the widgets read (design §13.3).
@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    private let generatedAt = Date(timeIntervalSince1970: 1_792_880_000)

    private var sample: WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: generatedAt,
            playerName: "Noah",
            standing: StandingSnapshot(rank: 13, scopeLabel: "Global", rating: 1086, weeklyMovement: 2, gamesPlayed: 41),
            rivalry: RivalrySnapshot(
                rivalID: PreviewData.anaSeat.rawValue,
                rivalName: "Ana",
                rivalAvatar: .emoji(emoji: "🦊", colorIndex: 0),
                myAvatar: .curated(id: "crow"),
                myWins: 5,
                theirWins: 12,
                line: "Ana 12, you 5. Ana's living in your head rent-free."
            ),
            nextBadge: BadgeSnapshot(badgeID: "BG-19", name: "Three-Peat", tier: .red, progress: 1, target: 3, progressLine: "1 of 3 wins in a row")
        )
    }

    private func temporaryStore() -> WidgetSnapshotStore {
        WidgetSnapshotStore(fileURL: URL.temporaryDirectory.appending(path: "widget-\(UUID().uuidString).json"))
    }

    @Test("Encodes with sorted keys and ISO 8601 dates, and round-trips")
    func encoding() throws {
        let data = try SharedJSON.encoder().encode(sample)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.hasPrefix(#"{"generatedAt":"2026-10-24T22:13:20Z""#))
        #expect(json.contains(#""version":1"#))
        #expect(json.contains(#""tier":"red""#))
        #expect(json.contains(#""rivalAvatar":{"emoji":{"colorIndex":0,"emoji":"🦊"}}"#))
        let decoded = try SharedJSON.decoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded == sample)
    }

    @Test("Optional sections are omitted, and an empty snapshot decodes")
    func optionalSections() throws {
        let data = try SharedJSON.encoder().encode(WidgetSnapshot.empty)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["generatedAt", "playerName", "version"])
        #expect(try SharedJSON.decoder().decode(WidgetSnapshot.self, from: data) == .empty)
    }

    @Test("The store saves and loads; a newer version or garbage reads as nothing")
    func store() throws {
        let store = temporaryStore()
        #expect(store.load() == nil)
        try store.save(sample)
        #expect(store.load() == sample)

        var future = sample
        future.version = WidgetSnapshot.currentVersion + 1
        try store.save(future)
        #expect(store.load() == nil)

        let url = try #require(store.fileURL)
        try Data("not json".utf8).write(to: url)
        #expect(store.load() == nil)
        try? FileManager.default.removeItem(at: url)
    }

    @Test("A store without an app group does nothing")
    func noAppGroup() throws {
        let store = WidgetSnapshotStore(fileURL: nil)
        try store.save(sample)
        #expect(store.load() == nil)
    }

    @Test("The 5-step meter and badge progress clamp")
    func meters() {
        #expect(StandingSnapshot(rank: nil, scopeLabel: "Global", rating: nil, weeklyMovement: 0, gamesPlayed: 3).meterSteps == 3)
        #expect(StandingSnapshot(rank: nil, scopeLabel: "Global", rating: nil, weeklyMovement: 0, gamesPlayed: -1).meterSteps == 0)
        #expect(StandingSnapshot(rank: 4, scopeLabel: "Global", rating: 1000, weeklyMovement: 0, gamesPlayed: 9).meterSteps == 5)
        #expect(!StandingSnapshot(rank: nil, scopeLabel: "Global", rating: nil, weeklyMovement: 0, gamesPlayed: 3).isRanked)
        #expect(sample.standing?.isRanked == true)
        #expect(BadgeSnapshot(badgeID: "x", name: "x", tier: .gold, progress: 7, target: 5, progressLine: "").fraction == 1)
        #expect(BadgeSnapshot(badgeID: "x", name: "x", tier: .gold, progress: 1, target: 0, progressLine: "").fraction == 0)
    }

    @Test("Publishing waits while a live game is in progress (widgets frozen)")
    func publisherFreeze() {
        let store = temporaryStore()
        var reloads = 0
        let publisher = WidgetSnapshotPublisher(store: store) { reloads += 1 }

        publisher.isFrozen = true
        publisher.publish(sample, reason: .gameFinished)
        #expect(store.load() == nil)
        #expect(reloads == 0)
        #expect(publisher.current == sample)

        publisher.isFrozen = false
        #expect(store.load() == sample)
        #expect(reloads == 1)
        #expect(publisher.pending == nil)

        var claimed = sample
        claimed.playerName = "Sam"
        publisher.publish(claimed, reason: .claim)
        #expect(store.load() == claimed)
        #expect(reloads == 2)
        if let url = store.fileURL { try? FileManager.default.removeItem(at: url) }
    }
}
