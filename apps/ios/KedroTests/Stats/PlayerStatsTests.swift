import Foundation
import Testing
@testable import Kedro

@Suite("Lifetime stats (PRD §5.1)")
struct PlayerStatsTests {
    private let sample = StatsSnapshot.build([PreviewData.sampleState(throughRound: 8, finished: true)])

    @Test("Noah in the sample game")
    func noah() throws {
        let stats = try #require(sample.stats(for: PreviewData.noah.ref))
        #expect(stats.gamesPlayed == 1)
        #expect(stats.wins == 1)
        #expect(stats.winRate == 1)
        #expect(stats.bestGame?.score == 28)
        #expect(stats.worstGame?.score == 28)
        #expect(stats.averageScorePerGame == 28)
        #expect(stats.roundsPlayed == 8)
        #expect(stats.averageScorePerRound == 3.5)
        #expect(stats.knocks == 3)
        #expect(stats.landed == 2)
        #expect(stats.tied == 0)
        #expect(stats.failed == 1)
        #expect(stats.knockRate == 3.0 / 8.0)
        #expect(stats.knockSuccessRate == 2.0 / 3.0)
        #expect(stats.currentWinStreak == 1)
        #expect(stats.longestWinStreak == 1)
        #expect(stats.form == [Rank(position: 1, isShared: false)])
        #expect(stats.nemesis == nil)
    }

    @Test("Ana's knocks and nemesis")
    func ana() throws {
        let stats = try #require(sample.stats(for: PreviewData.ana.ref))
        #expect(stats.landed == 1)
        #expect(stats.tied == 1)
        #expect(stats.failed == 0)
        #expect(stats.knockSuccessRate == 0.5)
        #expect(stats.nemesis == PreviewData.noah.ref)
        #expect(stats.nemesisCount == 1)
        #expect(stats.wins == 0)
        #expect(stats.currentWinStreak == 0)
    }

    @Test("Streaks: current and longest")
    func streaks() throws {
        var history = StatsHistory()
        let a = TestPerson.player("A"), b = TestPerson.player("B"), c = TestPerson.player("C")
        for winner in [0, 0, 0, 1, 0, 0] { history.win([a, b, c], winner: winner) }
        let stats = try #require(history.snapshot().stats(for: a.ref))
        #expect(stats.longestWinStreak == 3)
        #expect(stats.currentWinStreak == 2)
        #expect(stats.wins == 5)
        #expect(stats.form.map(\.position) == [1, 1, 2, 1, 1])
    }

    @Test("Shared wins count for every tied winner")
    func sharedWins() throws {
        var history = StatsHistory()
        let a = TestPerson.player("A"), b = TestPerson.player("B"), c = TestPerson.player("C")
        history.game([a, b, c], [([4, 4, 9], 2)])
        let snapshot = history.snapshot()
        #expect(snapshot.stats(for: a.ref)?.wins == 1)
        #expect(snapshot.stats(for: b.ref)?.wins == 1)
        #expect(snapshot.stats(for: c.ref)?.wins == 0)
    }

    @Test("Nemesis ties go to whoever got there first")
    func nemesisTie() throws {
        var history = StatsHistory()
        let me = TestPerson.player("Me"), b = TestPerson.player("B"), c = TestPerson.player("C"), d = TestPerson.player("D")
        history.ordered([b, me, c, d]) // B ahead
        history.ordered([c, me, b, d]) // C ahead
        let snapshot = history.snapshot()
        #expect(snapshot.stats(for: me.ref)?.nemesis == b.ref)
        #expect(snapshot.stats(for: me.ref)?.nemesisCount == 1)
    }

    @Test("Head-to-head: Noah and Ana in the sample game")
    func headToHead() {
        let h2h = sample.headToHead(PreviewData.noah.ref, PreviewData.ana.ref)
        #expect(h2h.gamesTogether == 1)
        #expect(h2h.aAhead == 1)
        #expect(h2h.bAhead == 0)
        #expect(h2h.aWins == 1)
        #expect(h2h.bWins == 0)
        #expect(h2h.aKnocks == KnockTally(landed: 2, tied: 0, failed: 1))
        #expect(h2h.bKnocks == KnockTally(landed: 1, tied: 1, failed: 0))
        #expect(h2h.lastMeeting?.aScore == 28)
        #expect(h2h.lastMeeting?.bScore == 34)
        #expect(h2h.leader == PreviewData.noah.ref)
        #expect(h2h.aKnocks.label == "✓2 =0 ✗1")
    }

    @Test("Head-to-head across the demo history is symmetric")
    func headToHeadSymmetric() {
        let snapshot = StatsSnapshot.build(PreviewData.demoStates)
        let forward = snapshot.headToHead(PreviewData.noah.ref, PreviewData.ana.ref)
        let backward = snapshot.headToHead(PreviewData.ana.ref, PreviewData.noah.ref)
        #expect(forward.gamesTogether == backward.gamesTogether)
        #expect(forward.aAhead == backward.bAhead)
        #expect(forward.aWins == backward.bWins)
        #expect(forward.gamesTogether == snapshot.record(PreviewData.noah.ref)?.sharedGames[PreviewData.ana.ref])
    }

    @Test("A claimed guest's games count for the account from game 1")
    func claims() throws {
        var history = StatsHistory()
        let guest = TestPerson.guest("Sam"), account = TestPerson.player("Sam")
        let a = TestPerson.player("A"), b = TestPerson.player("B")
        for _ in 0..<3 { history.win([a, b, guest], winner: 2) }
        history.win([a, b, account], winner: 0)
        let unclaimed = history.snapshot()
        #expect(unclaimed.record(guest.ref)?.gamesPlayed == 3)
        #expect(unclaimed.record(account.ref)?.gamesPlayed == 1)

        let claimed = history.snapshot(StatsOptions(aliases: [guest.ref: account.ref]))
        let record = try #require(claimed.record(account.ref))
        #expect(record.gamesPlayed == 4)
        #expect(record.wins == 3)
        #expect(claimed.records[guest.ref] == nil)
        #expect(record.badges[.firstBlood]?.gameIndex == 0)
        // Looking up the guest identity resolves to the account.
        #expect(claimed.record(guest.ref)?.ref == account.ref)
    }

    @Test("Edited rounds are reflected (stats read the fold, never counters)")
    func editsFlowThrough() throws {
        var game = TestGame(players: 3)
        game.setUp(planned: 1)
        game.record([0, 5, 6], knocker: 0)
        game.add(.roundEdited(.init(round: game.round(1, [9, 5, 6], knocker: 0))))
        game.add(.gameFinished(.init(reason: .completed, finalRounds: [game.round(1, [9, 5, 6], knocker: 0)])))
        var options = StatsOptions()
        options.minimumRounds = 1 // a one-round game, below the 3-round rule
        let snapshot = StatsSnapshot.build([game.state], options: options)
        let stats = try #require(snapshot.stats(for: game.seats[0].player))
        #expect(stats.failed == 1)
        #expect(stats.bestGame?.score == 19)
    }
}
