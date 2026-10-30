import Foundation
import Testing
@testable import Kedro

@Suite("Ratings (pairwise Elo)")
struct RatingsTests {
    @Test("Every game is zero-sum across the generated history")
    func zeroSumPerGame() {
        let snapshot = StatsSnapshot.build(PreviewData.demoStates)
        #expect(snapshot.games.count == 41)
        for game in snapshot.games {
            let changes = snapshot.ratingChanges(for: game.id).values
            #expect(changes.count == game.playerCount)
            let sum = changes.reduce(0.0) { $0 + ($1.after - $1.before) }
            #expect(abs(sum) < 1e-9, "game \(game.index) drifted by \(sum)")
        }
        // The pool is conserved: the average rating is still 1,000.
        let ratings = snapshot.records.values.map(\.rating)
        let mean = ratings.reduce(0, +) / Double(ratings.count)
        #expect(abs(mean - Ratings.startingRating) < 1e-6)
    }

    @Test("Sample game from scratch: double K, scaled by 1/(n−1)")
    func sampleGameFromScratch() {
        let snapshot = StatsSnapshot.build([PreviewData.sampleState(throughRound: 8, finished: true)])
        let changes = snapshot.ratingChanges(for: PreviewData.sampleGameID)
        // Everyone at 1,000 and provisional (K 64): each pair is worth 64 / 4 × 0.5 = 8 points.
        #expect(changes[PreviewData.noah.ref]?.delta == 32)
        #expect(changes[PreviewData.ana.ref]?.delta == 16)
        #expect(changes[PreviewData.cleo.ref]?.delta == 0)
        #expect(changes[PreviewData.ben.ref]?.delta == -16)
        #expect(changes[.guest(PreviewData.samID)]?.delta == -32)
        // Hidden until game 5.
        #expect(changes.values.allSatisfy { !$0.isRated && !$0.isDebut })
    }

    @Test("K is 64 for the first 10 games, then 32; a pair uses the larger")
    func kFactor() {
        #expect(Ratings.k(gamesBefore: 0) == 64)
        #expect(Ratings.k(gamesBefore: 9) == 64)
        #expect(Ratings.k(gamesBefore: 10) == 32)
        let deltas = Ratings.deltas(totals: ["a": 10, "b": 20], ratings: ["a": 1000, "b": 1000], gamesBefore: ["a": 30, "b": 0])
        #expect(deltas["a"] == 32)
        #expect(deltas["b"] == -32)
        let established = Ratings.deltas(totals: ["a": 10, "b": 20], ratings: ["a": 1000, "b": 1000], gamesBefore: ["a": 30, "b": 30])
        #expect(established["a"] == 16)
    }

    @Test("Equal totals are a draw: equal ratings don't move")
    func draws() {
        let deltas = Ratings.deltas(totals: ["a": 10, "b": 10, "c": 10], ratings: [:], gamesBefore: [:])
        #expect(deltas.values.allSatisfy { $0 == 0 })
        // An underdog's draw gains.
        let upset = Ratings.deltas(totals: ["a": 10, "b": 10], ratings: ["a": 900, "b": 1100], gamesBefore: [:])
        #expect((upset["a"] ?? 0) > 0)
    }

    @Test("Ben's 10th game is his debut, revealed to the whole table")
    func benDebut() throws {
        let snapshot = StatsSnapshot.build(PreviewData.demoStates)
        let before = snapshot.before(PreviewData.sampleGameID)
        #expect(before.record(PreviewData.ben.ref)?.gamesPlayed == Ratings.rankedAfterGames - 1)
        #expect(before.record(PreviewData.ben.ref)?.isRanked == false)
        let change = try #require(snapshot.ratingChanges(for: PreviewData.sampleGameID)[PreviewData.ben.ref])
        #expect(change.isDebut)
        #expect(change.isRated)
        #expect(snapshot.record(PreviewData.ben.ref)?.isRanked == true)
        let progression = try #require(snapshot.gameEnd(for: PreviewData.sampleGameID, viewer: PreviewData.noah.ref))
        #expect(progression.debuts.map(\.player) == [PreviewData.ben.ref])
        #expect(progression.debuts.first?.rating == change.displayAfter)
        // Sam is on game 3: rated nothing yet.
        #expect(progression.ratingChange(for: .guest(PreviewData.samID))?.isRated == false)
    }

    @Test("Replay is deterministic and order-independent in the input")
    func deterministic() {
        let states = PreviewData.demoStates
        let a = StatsSnapshot.build(states)
        let b = StatsSnapshot.build(states.reversed())
        for (ref, record) in a.records {
            #expect(b.records[ref]?.rating == record.rating)
        }
    }

    @Test("Abandoned games never count")
    func abandonedIgnored() {
        var history = StatsHistory()
        let a = TestPerson.player("A"), b = TestPerson.player("B"), c = TestPerson.player("C")
        history.win([a, b, c], winner: 0)
        history.game([a, b, c], [([0, 5, 5], 0)], abandoned: true)
        let snapshot = history.snapshot()
        #expect(snapshot.games.count == 1)
        #expect(snapshot.record(a.ref)?.gamesPlayed == 1)
    }
}
