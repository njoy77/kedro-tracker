import Foundation
import Testing
@testable import Kedro

/// A tiny deterministic generator (SplitMix64) for generated histories.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Ratings on generated history")
struct GeneratedHistoryTests {
    @Test("Every game sums to zero and the pool stays at 1,000 (3–8 players, mixed guests)")
    func zeroSum() {
        var random = SeededGenerator(seed: 2026)
        let pool = (0..<10).map { TestPerson.player("P\($0)") } + (0..<3).map { TestPerson.guest("G\($0)") }
        var history = StatsHistory()
        for _ in 0..<80 {
            let size = Int.random(in: 3...8, using: &random)
            let people = Array(pool.shuffled(using: &random).prefix(size))
            let rounds = (0..<Int.random(in: 1...8, using: &random)).map { _ in
                (people.map { _ in Int.random(in: -2...30, using: &random) }, Int.random(in: 0..<size, using: &random))
            }
            history.game(people, rounds)
        }
        let snapshot = history.snapshot()
        #expect(snapshot.games.count == 80)
        for game in snapshot.games {
            let sum = snapshot.ratingChanges(for: game.id).values.reduce(0.0) { $0 + $1.after - $1.before }
            #expect(abs(sum) < 1e-9)
        }
        let ratings = snapshot.records.values.map(\.rating)
        #expect(abs(ratings.reduce(0, +) / Double(ratings.count) - Ratings.startingRating) < 1e-6)
        // Rebuilding gives identical ratings (the replay is deterministic).
        let again = history.snapshot()
        for (ref, record) in snapshot.records { #expect(again.records[ref]?.rating == record.rating) }
    }

    @Test("K scaled by 1/(n−1): three newcomers in finishing order")
    func threePlayers() {
        let deltas = Ratings.deltas(totals: ["a": 1, "b": 2, "c": 3], ratings: [:], gamesBefore: [:], order: ["a", "b", "c"])
        // Each pair is worth 64 / 2 × 0.5 = 16.
        #expect(deltas["a"] == 32)
        #expect(deltas["b"] == 0)
        #expect(deltas["c"] == -32)
    }
}

@Suite("Play-more incentives (design §12.5)")
struct StakesTests {
    private let people = ["A", "B", "C", "D", "E", "F"].map { TestPerson.player($0) }
    private let clean = Voice(level: .clean)

    @Test("Game 5 is the stakes: J-01 with the meter")
    func rankThreshold() {
        var history = StatsHistory()
        for _ in 0..<4 { history.win(Array(people.prefix(3)), winner: 1) }
        let stakes = history.snapshot().tonightsStakes(for: people[0].ref, table: [people[1].ref], voice: clean)
        #expect(stakes.kind == .rankThreshold)
        #expect(stakes.meter == 4)
        #expect(stakes.text == clean.line("J-01"))
    }

    @Test("A rival at the table: J-05; nothing on the line: J-10")
    func rivalry() {
        var history = StatsHistory()
        for _ in 0..<2 { history.ordered([people[1], people[0], people[2]]) }
        let snapshot = history.snapshot()
        let stakes = snapshot.tonightsStakes(for: people[0].ref, table: [people[1].ref, people[2].ref], voice: clean)
        #expect(stakes.kind == .levelRivalry(people[1].ref))
        #expect(stakes.text == "B leads you 2–0. Tonight's a good night to fix that.")
        let stranger = TestPerson.player("New")
        #expect(snapshot.tonightsStakes(for: stranger.ref, table: [], voice: clean).kind == .nothing)
    }

    @Test("Since you last looked: last game, and who passed you")
    func sinceYouLastLooked() throws {
        var history = StatsHistory()
        for _ in 0..<5 { history.win(people, winner: 0) }
        let firstFive = history.snapshot()
        let since = try #require(firstFive.games.last?.finishedAt).addingTimeInterval(3600)
        for _ in 0..<4 { history.win(people, winner: 1) }
        let snapshot = history.snapshot()
        let items = snapshot.sinceYouLastLooked(for: people[0].ref, since: since, voice: clean)
        #expect(items.contains { $0.kind == .passed(people[1].ref) && $0.text == "B passed you on the board." })
        let last = try #require(items.first)
        guard case .lastGame = last.kind else {
            Issue.record("the last game comes first")
            return
        }
        #expect(last.text.hasPrefix("2nd at Test Table. Rating \u{2212}"))
        // Nothing new: no last-game line.
        let later = snapshot.sinceYouLastLooked(for: people[0].ref, since: .distantFuture, voice: clean)
        #expect(!later.contains { if case .lastGame = $0.kind { true } else { false } })
    }

    @Test("Wrapped: 10 games, December 1, then it stays until next year")
    func wrapped() throws {
        var history = StatsHistory()
        let three = Array(people.prefix(3))
        for _ in 0..<12 { history.win(three, winner: 0) }
        let snapshot = history.snapshot()
        let calendar = StatsHistory.utc
        func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
        }
        let me = three[0].ref
        let november = try date(2026, 11, 1), december = try date(2026, 12, 2)
        let march = try date(2027, 3, 1), june = try date(2026, 6, 1)
        let release = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        #expect(snapshot.wrappedAvailability(for: me, year: 2026, now: november) == .arrives(release))
        #expect(snapshot.wrappedAvailability(for: me, year: 2026, now: december) == .available)
        #expect(snapshot.wrappedSlot(for: me, voice: clean, now: december)?.state == .ready)
        #expect(snapshot.wrappedSlot(for: me, voice: clean, now: march)?.year == 2026)
        #expect(snapshot.wrappedSlot(for: me, voice: clean, now: june) == nil)

        let summary = try #require(snapshot.wrapped(for: me, year: 2026, now: december))
        #expect(summary.games == 12)
        #expect(summary.wins == 12)
        #expect(summary.ratingLine.count == 13)
        #expect(summary.ratingStart == 1000)
        #expect(summary.ratingPeak == summary.ratingNow)
        #expect(summary.knocks == 12)
        #expect(summary.persona == .closer)
        #expect(summary.victim != nil)
        #expect(summary.nemesis == nil)
        #expect(WrappedCard.cards(for: summary).count == (summary.shame.isEmpty ? 11 : 12))
        #expect(WrappedPersona.roast(clean.line(summary.persona.copyID)) == "When you knock, people fold.")

        var short = StatsHistory()
        for _ in 0..<6 { short.win(three, winner: 0) }
        let slot = try #require(short.snapshot().wrappedSlot(for: me, voice: clean, now: december))
        #expect(slot.state == .needsGames(played: 6, needed: 10))
        #expect(slot.text == "Play 4 more games this year to get your Wrapped. (6 of 10)")
        #expect(short.snapshot().wrapped(for: me, year: 2026) == nil)
    }

    @Test("The sample game's progression for the table agent")
    func sampleProgression() throws {
        let snapshot = StatsSnapshot.build(PreviewData.demoStates)
        let progression = try #require(snapshot.gameEnd(for: PreviewData.sampleGameID, viewer: PreviewData.noah.ref))
        #expect(progression.ratingChanges.map(\.player) == PreviewData.sampleSeats.map(\.player))
        #expect(abs(progression.ratingChanges.reduce(0.0) { $0 + $1.after - $1.before }) < 1e-9)
        #expect(progression.viewerRank != nil)
        let ben = try #require(progression.debuts.first)
        #expect(progression.debutLine(ben, voice: clean).hasPrefix("Ben's on the board. "))
        let titles = snapshot.tableTitles(for: PreviewData.sampleSeats)
        for seat in PreviewData.sampleSeats {
            if let title = titles[seat.id] {
                #expect(snapshot.availableTitles(of: seat.player).contains(title) || snapshot.bestEarnedTitle(of: seat.player) == title)
            }
        }
        #expect(snapshot.gamesPlayed(for: PreviewData.sampleSeats)[PreviewData.benSeat] == 5)
    }
}
