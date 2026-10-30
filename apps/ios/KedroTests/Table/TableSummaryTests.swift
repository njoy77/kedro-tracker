import Foundation
import Testing
@testable import Kedro

@Suite("Corrections")
@MainActor
struct CorrectionPreviewTests {
    private func session() -> GameSession {
        let operations = PreviewData.sampleOperations(throughRound: 5, finished: false)
        return GameSession(
            gameID: PreviewData.sampleGameID, operations: operations,
            store: InMemoryGameStore(operations: operations), transport: LocalOnlyTransport(),
            identity: PreviewData.noahIdentity, clock: HybridLogicalClock(device: PreviewData.noahPhone)
        )
    }

    @Test("What changes: Sam's R4 −1 → 3 flips Cleo's knock and needs a confirmation")
    func knockFlip() throws {
        let session = session()
        var hands = PreviewData.sampleRounds[3].hands
        hands[PreviewData.samSeat] = 3
        let edited = Round(number: 4, hands: hands, knocker: PreviewData.cleoSeat)
        let preview = CorrectionPreview(before: session.state, after: session.preview(.roundEdited(.init(round: edited))), roundNumber: 4)

        let cleo = try #require(preview.lines.first { $0.seat == PreviewData.cleoSeat })
        #expect(cleo.round == Change(before: 12, after: -10))
        #expect(cleo.total == Change(before: 45, after: 23))
        let sam = try #require(preview.lines.first { $0.seat == PreviewData.samSeat })
        #expect(sam.round == Change(before: -1, after: 3))
        #expect(sam.total == Change(before: 47, after: 51))
        #expect(preview.lines.count == 2, "Nobody else moves")
        #expect(preview.outcome == Change(before: .failed, after: .landed))
        #expect(preview.needsConfirmation)
        #expect(preview.confirmationText(name: session.state.name(of:)) == "Cleo's knock: failed → landed, 12 → −10. Everyone sees this.")
        #expect(preview.text(for: sam, name: session.state.name(of:)) == "Sam: R4 −1 → 3 · total 47 → 51")
    }

    @Test("A value change that keeps the outcome saves without asking")
    func noFlip() {
        let session = session()
        var hands = PreviewData.sampleRounds[0].hands
        hands[PreviewData.benSeat] = 21
        let edited = Round(number: 1, hands: hands, knocker: PreviewData.anaSeat)
        let preview = CorrectionPreview(before: session.state, after: session.preview(.roundEdited(.init(round: edited))), roundNumber: 1)
        #expect(preview.lines.map(\.seat) == [PreviewData.benSeat])
        #expect(!preview.needsConfirmation)
    }

    @Test("Changing the knocker always asks")
    func knockerChange() {
        let session = session()
        let edited = Round(number: 5, hands: PreviewData.sampleRounds[4].hands, knocker: PreviewData.samSeat)
        let preview = CorrectionPreview(before: session.state, after: session.preview(.roundEdited(.init(round: edited))), roundNumber: 5)
        #expect(preview.knocker == Change(before: PreviewData.noahSeat, after: PreviewData.samSeat))
        #expect(preview.needsConfirmation)
        #expect(preview.confirmationText(name: session.state.name(of:)) == "The R5 knocker changes from Noah to Sam. Everyone sees this.")
    }
}

@Suite("Game end")
struct GameEndSummaryTests {
    private let state = PreviewData.sampleState(throughRound: 8, finished: true)

    @Test("Noah wins from 4th after Round 3 (W-02); Sam is dead last (W-10)")
    func winnerLines() throws {
        let summary = GameEndSummary(state)
        #expect(summary.winners == [PreviewData.noahSeat])
        let headline = try #require(summary.headline)
        #expect(headline.render(Voice(level: .clean), gameID: state.gameID, round: 8) == "Noah wins. Obviously.")
        let line = try #require(summary.winnerLine)
        #expect(line.render(Voice(level: .clean), gameID: state.gameID, round: 8) == "4th after Round 3. Won it anyway. Ice in the veins.")
        let last = try #require(summary.lastPlaceLine)
        #expect(last.render(Voice(level: .clean), gameID: state.gameID, round: 8) == "Sam: 70. Dead last.")
        #expect(summary.lostByOne == nil)
    }

    @Test("Knock records per player and for the table")
    func knockRecords() {
        let summary = GameEndSummary(state)
        #expect(summary.knockRecords[PreviewData.noahSeat]?.text == "✓2 ✗1")
        #expect(summary.knockRecords[PreviewData.anaSeat]?.text == "✓1 =1")
        #expect(summary.knockRecords[PreviewData.benSeat]?.text == "=1")
        #expect(summary.highlights.contains(.knocks(landed: 4, tied: 2, failed: 2)))
    }

    @Test("A late joiner who never played isn't last; an inherent knock gets its own highlight")
    func lateJoinerAndWentOut() {
        var game = TestGame()
        game.setUp()
        game.add(.roundRecorded(.init(round: Round(number: 1, hands: game.round(1, [0, 3, -1], knocker: 0).hands, knocker: game.seat(0), isInherent: true))))
        let latecomer = Seat(player: .guest(GuestID()), displayName: "Late", order: 9)
        game.add(.playerSeated(.init(seat: latecomer)))
        game.add(.gameFinished(.init(reason: .endedEarly, finalRounds: game.state.rounds.map(\.round))))
        let summary = GameEndSummary(game.state)
        let last = summary.lastPlaceLine?.render(Voice(level: .clean), gameID: game.gameID, round: 1)
        #expect(last == "P1: 3. Dead last.")
        #expect(summary.highlights.contains(.wentOut(count: 1, landed: 0)))
        #expect(!summary.highlights.contains { if case .knocks = $0 { true } else { false } })
    }

    @Test("Run It Back: same seats clockwise from the host, first deal rotates one seat")
    func rematch() throws {
        let plan = try #require(Rematch(from: state, host: PreviewData.anaSeat))
        #expect(plan.others.map(\.id) == [PreviewData.benSeat, PreviewData.cleoSeat, PreviewData.samSeat, PreviewData.noahSeat])
        #expect(plan.others.map(\.order) == [1, 2, 3, 4])
        #expect(plan.config.firstDealerSeat == PreviewData.anaSeat, "Noah dealt first last time")
        #expect(plan.config.plannedRounds == 8)
        #expect(plan.config.tableWord != state.config.tableWord)
        let ben = try #require(plan.others.first)
        #expect(ben.gamesPlayed == (state.seat(PreviewData.benSeat)?.gamesPlayed).map { $0 + 1 })
        #expect(Rematch(from: state, host: PlayerRef.player(PlayerID()).seatID) == nil)
    }
}

@Suite("Table voice")
struct TableVoiceTests {
    @Test("Roasts by outcome: landed, red King, failed, tied, learner")
    func roasts() throws {
        let state = PreviewData.sampleState(throughRound: 5)
        let r5 = try #require(state.round(5))
        #expect(TableVoice.roast(for: r5, in: state, viewer: nil, viewerIsLearner: false)?.ids == VoiceMoment.knockLanded.variantIDs)
        let r4 = try #require(state.round(4))
        #expect(TableVoice.roast(for: r4, in: state, viewer: nil, viewerIsLearner: false)?.ids == ["K-12"], "Sam's red King decided it")
        let r3 = try #require(state.round(3))
        #expect(TableVoice.roast(for: r3, in: state, viewer: nil, viewerIsLearner: false)?.ids == VoiceMoment.knockFailed.variantIDs)
        #expect(TableVoice.roast(for: r3, in: state, viewer: PreviewData.anaSeat, viewerIsLearner: false)?.ids == ["K-10"], "Ana beat the knocker")
        #expect(TableVoice.roast(for: r3, in: state, viewer: PreviewData.noahSeat, viewerIsLearner: true)?.ids == ["K-30"])
        let r2 = try #require(state.round(2))
        #expect(TableVoice.roast(for: r2, in: state, viewer: nil, viewerIsLearner: false)?.ids == VoiceMoment.knockTied.variantIDs)
    }

    @Test("Banter: a tie at the top")
    func tieAtTop() throws {
        var game = TestGame(players: 3)
        game.setUp()
        game.record([5, 5, 9], knocker: 2)
        let banter = try #require(TableVoice.banter(for: game.state))
        #expect(banter.ids == ["B-05"])
    }

    @Test("Banter: the round someone is first cooked beats a new leader")
    func newlyCooked() throws {
        var game = TestGame(players: 3)
        game.setUp(planned: 4)
        game.record([5, 3, 6], knocker: 1)  // P1 −10 leads; P2 is 16 back with 3 to play (not cooked)
        game.record([2, 9, 30], knocker: 0) // P0 −10 takes the lead; P2 is 41 back with 2 to play
        let banter = try #require(TableVoice.banter(for: game.state))
        #expect(banter.ids == ["B-03"])
        #expect(banter.render(Voice(level: .clean), gameID: game.gameID, round: 2) == "P2's 41 back with 2 to play. Cooked.")
    }

    @Test("Seat order puts you first in the live knock picker")
    func youFirst() {
        let seats = PreviewData.sampleSeats
        let ordered = LiveKnockSheet.youFirst(seats, me: PreviewData.benSeat)
        #expect(ordered.first?.id == PreviewData.benSeat)
        #expect(ordered.count == seats.count)
        #expect(LiveKnockSheet.youFirst(seats, me: nil).map(\.id) == seats.map(\.id))
    }
}
