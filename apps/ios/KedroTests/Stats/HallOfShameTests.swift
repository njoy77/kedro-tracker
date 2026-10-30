import Foundation
import Testing
@testable import Kedro

@Suite("Hall of Shame (design §12.8)")
struct HallOfShameTests {
    private let a = TestPerson.player("A"), b = TestPerson.player("B"), c = TestPerson.player("C"), d = TestPerson.player("D")
    private var table: [TestPerson] { [a, b, c, d] }

    /// Three learner games each (they never produce entries), the first with a monster hand.
    private func learnerGames(_ history: inout StatsHistory) {
        history.game(table, [([0, 5, 5, 90], 0)])
        history.win(table, winner: 1)
        history.win(table, winner: 2)
    }

    private func board(_ boards: [ShameBoard], _ category: ShameCategory) -> [ShameEntry] {
        boards.first { $0.category == category }?.entries ?? []
    }

    @Test("Each category's moment, with its numbers and roast")
    func categories() throws {
        var history = StatsHistory()
        learnerGames(&history)
        // R1: A knocks on 12 into B's −1 (failed, gap 13); D holds 47.
        // R2: A fails again (9 into a 2); B leads by a mile, then R3 C lands while B blows up.
        let game = history.game(table, [
            ([12, -1, 5, 47], 0),
            ([9, 2, 6, 8], 0),
            ([20, 40, 0, 3], 2),
        ])
        let snapshot = history.snapshot()
        let boards = snapshot.hallOfShame(viewer: a.ref)

        let worstHand = try #require(board(boards, .worstHand).first)
        #expect(worstHand.player == d.ref)
        #expect(worstHand.value == 47)       // the learner game's 90 doesn't count
        #expect(worstHand.roundNumber == 1)
        #expect(worstHand.detail == "held 47")

        let worstKnock = try #require(board(boards, .worstKnock).first)
        #expect(worstKnock.player == a.ref)
        #expect(worstKnock.value == 13)
        #expect(worstKnock.detail == "knocked on 12 into a \u{2212}1")
        #expect(Voice(level: .clean).line(worstKnock.category.copyID, worstKnock.roastArgs)
            == "Knocked on 12 into a \u{2212}1. Historians will study it.")

        let ateIt = try #require(board(boards, .ateIt).first)
        #expect(ateIt.player == a.ref)
        #expect(ateIt.value == 2)

        // Totals: A 22+19+20=61, B −1+2+40=41, C 5+6−10=1, D 47+8+3=58.
        let loss = try #require(board(boards, .biggestLoss).first)
        #expect(loss.player == a.ref)
        #expect(loss.value == 61)

        // B led after R2 (1 vs C's 11): up by 10, finished 2nd.
        let bottle = try #require(board(boards, .bottleJob).first { $0.player == b.ref })
        #expect(bottle.value == 10)
        #expect(bottle.finish?.position == 2)

        let hole = try #require(board(boards, .deepestHole).first)
        #expect(hole.player == a.ref)
        #expect(hole.value == 60)
        #expect(boards.allSatisfy { $0.entries.count <= 3 })
        #expect(snapshot.shameInductions(for: game, viewer: a.ref).contains { $0.category == .worstHand && $0.player == d.ref })
    }

    @Test("Top 3 per category, worst first; ties keep the earlier moment")
    func topThree() {
        var history = StatsHistory()
        learnerGames(&history)
        for hand in [30, 35, 30, 40, 20] {
            history.game(table, [([0, 5, 5, hand], 0)])
        }
        let entries = board(history.snapshot().hallOfShame(viewer: a.ref), .worstHand)
        #expect(entries.map(\.value) == [40, 35, 30])
        #expect(entries[2].gameIndex == 3) // the first 30
    }

    @Test("Scopes: your people, yours, and no global Hall")
    func scopes() {
        var history = StatsHistory()
        learnerGames(&history)
        history.game(table, [([12, -1, 5, 47], 0)])
        let stranger = TestPerson.player("Stranger"), e = TestPerson.player("E"), f = TestPerson.player("F")
        for _ in 0..<4 { history.win([stranger, e, f], winner: 0) }
        let snapshot = history.snapshot()

        let mine = snapshot.hallOfShame(scope: .yours, viewer: a.ref).flatMap(\.entries)
        #expect(!mine.isEmpty)
        #expect(mine.allSatisfy { $0.player == a.ref })
        // Strangers don't see A's moments, and A doesn't see theirs.
        #expect(snapshot.hallOfShame(viewer: stranger.ref).flatMap(\.entries).allSatisfy { $0.player != a.ref && $0.player != d.ref })
        #expect(snapshot.hallOfShame(viewer: a.ref).flatMap(\.entries).allSatisfy { $0.player != stranger.ref })
        // Blocked people are excluded.
        let blocked = history.snapshot(StatsOptions(excluded: [d.ref]))
        #expect(blocked.hallOfShame(viewer: a.ref).flatMap(\.entries).allSatisfy { $0.player != d.ref })
    }

    @Test("Learner games and abandoned games never produce entries")
    func learnersAndAbandoned() {
        var history = StatsHistory()
        history.game(table, [([0, 5, 5, 90], 0)])
        let snapshot = history.snapshot()
        #expect(snapshot.hallOfShame(viewer: a.ref).allSatisfy { $0.entries.isEmpty })

        var abandoned = StatsHistory()
        learnerGames(&abandoned)
        abandoned.game(table, [([0, 5, 5, 99], 0)], abandoned: true)
        #expect(board(abandoned.snapshot().hallOfShame(viewer: a.ref), .worstHand).isEmpty)
    }

    @Test("Game end shows the induction to the whole table")
    func gameEndInduction() throws {
        var history = StatsHistory()
        learnerGames(&history)
        let game = history.game(table, [([0, 5, 5, 47], 0)])
        let progression = try #require(history.snapshot().gameEnd(for: game, viewer: b.ref))
        let entry = try #require(progression.shameInductions.first { $0.category == .worstHand })
        #expect(entry.player == d.ref)
        #expect(progression.inductionLine(entry, voice: Voice(level: .clean)) == "New Hall of Shame entry: Worst Hand. Congratulations, D.")
    }
}
