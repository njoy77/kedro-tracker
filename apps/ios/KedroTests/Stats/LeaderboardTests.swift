import Foundation
import Testing
@testable import Kedro

@Suite("Leaderboard (design §12.4)")
struct LeaderboardTests {
    private let people = ["A", "B", "C", "D", "E", "F"].map { TestPerson.player($0) }

    /// Six players, five games each: A wins 3, B wins 2. G has 3 games; guest H has 6.
    private func history() -> (StatsHistory, g: TestPerson, h: TestPerson) {
        var history = StatsHistory()
        for winner in [0, 0, 1, 1, 0] { history.win(people, winner: winner) }
        let g = TestPerson.player("G"), h = TestPerson.guest("H")
        for _ in 0..<3 { history.win([people[0], g, people[1]], winner: 2) }
        for _ in 0..<6 { history.win([people[2], people[3], h], winner: 2) }
        return (history, g, h)
    }

    @Test("5-game eligibility; unclaimed guests never appear")
    func eligibility() {
        let (history, g, h) = history()
        let board = history.snapshot().leaderboard(scope: .global, sort: .rating, viewer: g.ref)
        #expect(board.ranked.count == 6)
        #expect(board.notYetRanked.map(\.ref) == [g.ref])
        #expect(board.viewerUnranked?.gamesLeft == 2)
        #expect(!board.ranked.contains { $0.ref == h.ref })
        #expect(!board.notYetRanked.contains { $0.ref == h.ref })
        // Ranks are 1…n for the sort, competition-style.
        #expect(board.ranked.first?.rank?.position == 1)
    }

    @Test("Per-sort minimums: win rate needs 10 games, knock success 15 knocks")
    func minimums() {
        let (history, _, _) = history()
        let snapshot = history.snapshot()
        let winRate = snapshot.leaderboard(scope: .global, sort: .winRate, viewer: people[0].ref)
        // A and B have 8 games, the rest 5 or 11: C and D played 11.
        #expect(Set(winRate.ranked.map(\.ref)) == [people[2].ref, people[3].ref])
        #expect(winRate.belowMinimum.allSatisfy { $0.rank == nil })
        #expect(winRate.belowMinimum.count == 4)
        let knocks = snapshot.leaderboard(scope: .global, sort: .knockSuccess, viewer: people[0].ref)
        #expect(knocks.ranked.isEmpty)
        #expect(knocks.belowMinimum.count == 6)
        #expect(Voice(level: .unhinged).line("L-05", ["n": 10]) == "Needs 10 games for this one.")
    }

    @Test("Avg score is ascending; wins descending with shared ranks")
    func sorting() throws {
        let (history, _, _) = history()
        let snapshot = history.snapshot()
        let avg = snapshot.leaderboard(scope: .global, sort: .avgScore, viewer: nil)
        let values = avg.ranked.map(\.value)
        #expect(values == values.sorted())
        let wins = snapshot.leaderboard(scope: .global, sort: .wins, viewer: nil)
        #expect(wins.ranked.map(\.value) == wins.ranked.map(\.value).sorted(by: >))
        // E and F have no wins: they share a rank.
        let e = try #require(wins.ranked.first { $0.ref == people[4].ref })
        #expect(e.rank?.isShared == true)
        #expect(e.valueText == "0")
    }

    @Test("Close race: the person above within the sort's threshold (L-04)")
    func closeRace() throws {
        var history = StatsHistory()
        for winner in [0, 0, 0, 1, 1] { history.win(people, winner: winner) }
        let board = history.snapshot().leaderboard(scope: .playedWith, sort: .wins, viewer: people[1].ref)
        let race = try #require(board.closeRace)
        #expect(race.above == people[0].ref)
        #expect(race.gapText == "1 win")
        #expect(Voice(level: .clean).line("L-04", ["name": race.name, "gap": race.gapText]) == "A's 1 win ahead of you. Very catchable.")
        // A, at the top, has nobody to chase.
        #expect(history.snapshot().leaderboard(scope: .playedWith, sort: .wins, viewer: people[0].ref).closeRace == nil)
    }

    @Test("Played With is you among the people you've shared a table with")
    func playedWith() {
        let (history, g, _) = history()
        let board = history.snapshot().leaderboard(scope: .playedWith, sort: .rating, viewer: g.ref)
        #expect(Set(board.ranked.map(\.ref)) == [people[0].ref, people[1].ref])
        #expect(board.notYetRanked.map(\.ref) == [g.ref])
    }

    @Test("Records: best game is lowest, ties go to whoever got there first")
    func records() {
        let (history, _, _) = history()
        let snapshot = history.snapshot()
        let best = snapshot.records(.bestGame, scope: .global, viewer: nil)
        #expect(best.first?.value == -10)
        #expect(best.first?.ref == people[0].ref)
        let games = snapshot.records(.mostGames, scope: .global, viewer: nil)
        #expect(games.first?.value == 11)
        #expect(games.prefix(2).allSatisfy { $0.rank == 1 })
        // B's three straight at G's table; H's six straight don't count (an unclaimed guest).
        let streak = snapshot.records(.longestStreak, scope: .global, viewer: nil).first
        #expect(streak?.value == 3)
        #expect(streak?.ref == people[1].ref)
    }

    @Test("Ratings show from game 5; progress meter until then")
    func progress() {
        let (history, g, _) = history()
        let snapshot = history.snapshot()
        let unranked = snapshot.progress(for: g.ref)
        #expect(unranked.meter == 3)
        #expect(unranked.rating == nil)
        #expect(unranked.meterLine(voice: Voice(level: .clean)) == "3 of 5. Finish 2 more and you're ranked.")
        let ranked = snapshot.progress(for: people[0].ref)
        #expect(ranked.meter == nil)
        #expect(ranked.rating != nil)
        #expect(ranked.globalRank != nil)
    }
}
