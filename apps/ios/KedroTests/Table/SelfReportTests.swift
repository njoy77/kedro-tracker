import Foundation
import Testing
@testable import Kedro

/// Self-report resolution (design §7.4): who knocked, the 5-second proposal ring with its untimed
/// Confirm, guest reporters and the shared reveal. Built from real operation logs so the fold and
/// the resolution agree.
@Suite("Self-report")
struct SelfReportTests {
    private func game(players: Int = 3) -> TestGame {
        var game = TestGame(players: players)
        game.setUp(planned: 6, mode: .selfReport)
        return game
    }

    private func report(_ game: inout TestGame, _ hands: [Int], knocked: Set<Int> = []) {
        for (index, hand) in hands.enumerated() {
            game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(index), hand: hand, knocked: knocked.contains(index))), actor: index)
        }
    }

    private func evaluate(_ game: TestGame, at wallMs: Int64) -> KnockerResolution {
        let state = game.state
        return KnockerResolution.evaluate(state.selfReport, seats: state.seats.map(\.id), now: Date(timeIntervalSince1970: TimeInterval(wallMs) / 1000))
    }

    @Test("Hands are collected until everyone has reported")
    func collecting() {
        var game = game()
        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(0), hand: 4, knocked: true)), actor: 0)
        #expect(evaluate(game, at: game.wallMs) == .collecting(waitingOn: [game.seat(1), game.seat(2)]))
        #expect(game.state.rounds.isEmpty)
    }

    @Test("Exactly one I knocked settles it, and the round saves itself")
    func oneClaim() throws {
        var game = game()
        report(&game, [4, 9, 6], knocked: [0])
        let record = try #require(game.state.lastRound)
        #expect(record.knocker == game.seat(0))
        #expect(record.outcome == .landed)
        #expect(record.recordedBy == "Everyone reported")
        #expect(game.state.selfReport == nil)
    }

    @Test("Nobody or several claimed: every phone asks Who knocked? (K-16 / K-15)")
    func undecided() {
        var nobody = game()
        report(&nobody, [4, 9, 6])
        let none = evaluate(nobody, at: nobody.wallMs)
        #expect(none == .undecided(claims: []))
        #expect(none.promptID == "K-16")
        #expect(none.needsDecision)

        var several = game()
        report(&several, [4, 9, 6], knocked: [0, 2])
        let two = evaluate(several, at: several.wallMs)
        #expect(two == .undecided(claims: [several.seat(0), several.seat(2)]))
        #expect(two.promptID == "K-15")
    }

    @Test("A proposal rings for 5 seconds, then it's ready to commit")
    func proposalRing() throws {
        var game = game()
        report(&game, [4, 9, 6])
        let proposedAt = game.wallMs + 1_000
        game.add(.knockerProposed(.init(roundNumber: 1, knocker: game.seat(0))), at: proposedAt, actor: 1)
        guard case let .proposed(proposal, deadline) = evaluate(game, at: proposedAt + 2_000) else {
            Issue.record("Expected a running proposal")
            return
        }
        #expect(proposal.knocker == game.seat(0))
        #expect(proposal.proposer == game.seat(1))
        #expect(deadline == Date(timeIntervalSince1970: TimeInterval(proposedAt + 5_000) / 1000))
        #expect(evaluate(game, at: proposedAt + 5_000) == .ready(game.seat(0)))

        game.add(.knockerResolved(.init(roundNumber: 1, knocker: game.seat(0))), at: proposedAt + 5_000, actor: 1)
        let record = try #require(game.state.lastRound)
        #expect(record.knocker == game.seat(0))
    }

    @Test("A different tap inside the ring is a contest (K-17)")
    func contest() {
        var game = game()
        report(&game, [4, 9, 6])
        let first = game.wallMs + 1_000
        game.add(.knockerProposed(.init(roundNumber: 1, knocker: game.seat(0))), at: first, actor: 1)
        game.add(.knockerProposed(.init(roundNumber: 1, knocker: game.seat(2))), at: first + 3_000, actor: 0)
        let resolution = evaluate(game, at: first + 10_000)
        guard case let .contested(earlier, later) = resolution else {
            Issue.record("Expected a contest, got \(resolution)")
            return
        }
        #expect(earlier.knocker == game.seat(0))
        #expect(later.knocker == game.seat(2))
        #expect(resolution.promptID == "K-17")
    }

    @Test("Agreeing inside the ring, or proposing after it, starts a clean ring")
    func agreeOrRestart() {
        var agree = game()
        report(&agree, [4, 9, 6])
        let start = agree.wallMs + 1_000
        agree.add(.knockerProposed(.init(roundNumber: 1, knocker: agree.seat(0))), at: start, actor: 1)
        agree.add(.knockerProposed(.init(roundNumber: 1, knocker: agree.seat(0))), at: start + 2_000, actor: 2)
        #expect(evaluate(agree, at: start + 8_000) == .ready(agree.seat(0)))

        var restart = game()
        report(&restart, [4, 9, 6])
        let early = restart.wallMs + 1_000
        restart.add(.knockerProposed(.init(roundNumber: 1, knocker: restart.seat(0))), at: early, actor: 1)
        restart.add(.knockerProposed(.init(roundNumber: 1, knocker: restart.seat(2))), at: early + 6_000, actor: 0)
        guard case let .proposed(latest, _) = evaluate(restart, at: early + 7_000) else {
            Issue.record("Expected a fresh ring")
            return
        }
        #expect(latest.knocker == restart.seat(2))
    }

    @Test("The proposer's phone commits at the deadline; VoiceOver makes it untimed; others back-stop")
    func commitTimes() {
        let me = PlayerRef.player(PlayerID()).seatID
        let other = PlayerRef.player(PlayerID()).seatID
        let at = Date(timeIntervalSince1970: 1_000)
        let proposal = KnockerProposal(opId: UUID(), proposer: me, proposerName: "Me", knocker: other, at: at)
        #expect(KnockerResolution.commitTime(for: proposal, mySeat: me, isUntimed: false) == at.addingTimeInterval(5))
        #expect(KnockerResolution.commitTime(for: proposal, mySeat: me, isUntimed: true) == nil)
        #expect(KnockerResolution.commitTime(for: proposal, mySeat: other, isUntimed: false) == at.addingTimeInterval(7))
        #expect(KnockerResolution.commitTime(for: proposal, mySeat: other, isUntimed: true) == at.addingTimeInterval(7))
    }

    @Test("The shared reveal hides a self-reported round until its reveal time on every phone")
    func sharedReveal() throws {
        var game = game()
        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(0), hand: 4, knocked: true)), actor: 0)
        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(1), hand: 9, knocked: false)), actor: 1)
        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(2), hand: 6, knocked: false)), actor: 2)
        let state = game.state
        let record = try #require(state.lastRound)
        let early = TableReveal.visibleState(state: state, operations: game.operations, now: record.recordedAt.addingTimeInterval(0.5))
        #expect(early.isHidden)
        #expect(early.state.rounds.isEmpty, "Shows the table as it was before the round")
        #expect(early.state.selfReport?.waitingOn == [game.seat(2)])
        let late = TableReveal.visibleState(state: state, operations: game.operations, now: SelfReportReveal.revealTime(for: record))
        #expect(!late.isHidden)
        #expect(late.state.rounds.count == 1)
    }

    @Test("Scorekeeper rounds are never hidden")
    func scorekeeperNotHidden() {
        let state = PreviewData.sampleState(throughRound: 5)
        let visible = TableReveal.visibleState(state: state, operations: PreviewData.sampleOperations(throughRound: 5, finished: false), now: .distantPast)
        #expect(!visible.isHidden)
    }
}

@Suite("Guest reporters")
struct GuestReporterTests {
    private let noah = Seat(player: .player(PlayerID()), displayName: "Noah", order: 0)
    private let sam = Seat(player: .guest(GuestID()), displayName: "Sam", order: 1)
    private let ana = Seat(player: .player(PlayerID()), displayName: "Ana", order: 2)
    private let jo = Seat(player: .guest(GuestID()), displayName: "Jo", order: 3)

    @Test("A guest's default reporter is the nearest player to their left (clockwise)")
    func defaultReporter() {
        let seats = [noah, sam, ana, jo]
        #expect(GuestReporters.reporter(for: sam, in: seats) == ana.id)
        #expect(GuestReporters.reporter(for: jo, in: seats) == noah.id, "Wraps around the table")
        #expect(GuestReporters.reporter(for: ana, in: seats) == ana.id, "Players report for themselves")
    }

    @Test("An assigned reporter wins, if they're a player at the table")
    func assignedReporter() {
        var assigned = sam
        assigned.reporter = noah.id
        #expect(GuestReporters.reporter(for: assigned, in: [noah, assigned, ana]) == noah.id)
        var bogus = sam
        bogus.reporter = jo.id
        #expect(GuestReporters.reporter(for: bogus, in: [noah, bogus, ana, jo]) == ana.id, "A guest can't report for a guest")
    }

    @Test("A phone reports its own seat first, then its guests")
    func reportedBy() {
        let seats = [noah, sam, ana, jo]
        #expect(GuestReporters.seats(reportedBy: ana.id, in: seats) == [ana.id, sam.id])
        #expect(GuestReporters.seats(reportedBy: noah.id, in: seats) == [noah.id, jo.id])
    }
}
