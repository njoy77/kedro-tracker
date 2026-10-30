import Foundation
import Testing
@testable import Kedro

@Suite("GameState.fold")
struct GameFoldTests {
    @Test("Lobby, then active on Deal")
    func lifecycle() {
        var game = TestGame()
        game.setUp(start: false)
        #expect(game.state.status == .lobby)
        #expect(game.state.seats.count == 3)
        #expect(game.state.currentDealer == game.seat(0)) // the host by default
        game.add(.gameStarted(.init(seatOrder: [game.seat(2), game.seat(0), game.seat(1)], firstDealer: game.seat(1))))
        #expect(game.state.status == .active)
        #expect(game.state.seats.map(\.id) == [game.seat(2), game.seat(0), game.seat(1)])
        #expect(game.state.currentDealer == game.seat(1))
    }

    @Test("The deal passes one seat left per saved round; undo moves it back")
    func dealerRotation() {
        var game = TestGame()
        game.setUp()
        #expect(game.state.currentDealer == game.seat(0))
        game.record([3, 9, 7], knocker: 0)
        #expect(game.state.currentDealer == game.seat(1))
        game.record([3, 9, 7], knocker: 0)
        #expect(game.state.currentDealer == game.seat(2))
        game.record([3, 9, 7], knocker: 0)
        #expect(game.state.currentDealer == game.seat(0)) // wraps
        game.add(.roundUndone(.init(roundNumber: 3)))
        #expect(game.state.currentDealer == game.seat(2))
        #expect(game.state.rounds.count == 2)
    }

    @Test("DealerChanged overrides, and the deal passes left from the correction")
    func dealerCorrection() {
        var game = TestGame(players: 4)
        game.setUp()
        game.record([3, 9, 7, 8], knocker: 0) // round 2 would be seat 1
        game.add(.dealerChanged(.init(roundNumber: 2, dealer: game.seat(3))), actor: 2)
        #expect(game.state.currentDealer == game.seat(3))
        game.record([3, 9, 7, 8], knocker: 0)
        #expect(game.state.currentDealer == game.seat(0))
        let entry = game.state.audit.last { if case .dealerChanged = $0.change { true } else { false } }
        #expect(entry?.summary == "P2 set the dealer to P3")
        // Editing an older round never changes the deal.
        game.add(.roundEdited(.init(round: game.round(1, [4, 9, 7, 8], knocker: 0))))
        #expect(game.state.currentDealer == game.seat(0))
    }

    @Test("Edits re-run scoring and are logged with before → after and effects")
    func edits() throws {
        var game = TestGame()
        game.setUp()
        game.record([3, 9, 7], knocker: 0) // landed: −10, 9, 7
        #expect(game.state.totals[game.seat(0)] == -10)
        game.add(.roundEdited(.init(round: game.round(1, [3, 2, 7], knocker: 0))), actor: 1)
        let state = game.state
        #expect(state.totals[game.seat(0)] == 13) // failed: 3 + 10
        #expect(state.rounds[0].outcome == .failed)
        #expect(state.rounds[0].isEdited)
        #expect(state.rounds[0].editedSeats == [game.seat(1)])
        let entry = try #require(state.audit.last)
        guard case let .roundEdited(round, hands, knocker, outcome) = entry.change else {
            Issue.record("Expected a round edit")
            return
        }
        #expect(round == 1)
        #expect(hands == [HandChange(seat: game.seat(1), before: 9, after: 2)])
        #expect(knocker == nil)
        #expect(outcome == Change(before: .landed, after: .failed))
        #expect(Set(entry.effects) == [
            ScoreEffect(seat: game.seat(0), before: -10, after: 13),
            ScoreEffect(seat: game.seat(1), before: 9, after: 2),
        ])
        #expect(entry.actor.name == "P1")
        #expect(entry.summary == "P1 changed P1's R1 hand 9 → 2")
    }

    @Test("Concurrent edits: the later HLC wins, whatever order they arrive in")
    func concurrentEdits() {
        var game = TestGame()
        game.setUp()
        game.record([3, 9, 7], knocker: 0)
        let base = game.wallMs
        game.add(.roundEdited(.init(round: game.round(1, [5, 9, 7], knocker: 0))), device: game.deviceB, at: base + 10_000)
        game.add(.roundEdited(.init(round: game.round(1, [4, 9, 7], knocker: 0))), device: game.deviceA, at: base + 5_000)
        let forward = GameState.fold(game.operations)
        let backward = GameState.fold(game.operations.reversed())
        #expect(forward == backward)
        #expect(forward.rounds[0].round.hands[game.seat(0)] == 5)
    }

    @Test("A round recorded twice keeps the earlier and offers the other")
    func duplicateRound() {
        var game = TestGame()
        game.setUp()
        let base = game.wallMs
        game.add(.roundRecorded(.init(round: game.round(1, [3, 9, 7], knocker: 0))), device: game.deviceB, at: base + 2_000)
        game.add(.roundRecorded(.init(round: game.round(1, [3, 9, 8], knocker: 0))), device: game.deviceA, at: base + 1_000)
        let state = GameState.fold(game.operations.shuffled())
        #expect(state.rounds.count == 1)
        #expect(state.rounds[0].round.hands[game.seat(2)] == 8) // device A's is earlier
        #expect(state.conflicts.count == 1)
        #expect(state.conflicts[0].rejected.hands[game.seat(2)] == 7)
        // An identical duplicate is not a conflict.
        game.add(.roundRecorded(.init(round: game.round(1, [3, 9, 8], knocker: 0))))
        #expect(game.state.conflicts.count == 1)
    }

    @Test("Finished games are immutable; late operations are surfaced")
    func finishedIsImmutable() {
        var game = TestGame()
        game.setUp(planned: 1)
        game.record([3, 9, 7], knocker: 0)
        #expect(game.state.isAwaitingFinish)
        game.add(.gameFinished(.init(reason: .completed, finalRounds: game.state.rounds.map(\.round))))
        let edit = game.add(.roundEdited(.init(round: game.round(1, [8, 9, 7], knocker: 0))), actor: 2)
        let state = game.state
        #expect(state.status == .finished)
        #expect(state.rounds[0].round.hands[game.seat(0)] == 3)
        #expect(state.lateOperations.map(\.id) == [edit.opId])
        #expect(state.lateOperations.first?.reason == .afterFinish)
        #expect(state.lateOperations.first?.actorName == "P2")
        #expect(state.currentDealer == nil)
        // Receipts and reactions are still allowed.
        game.add(.receiptSent(.init(fromSeat: game.seat(0), toSeat: game.seat(1), receiptKey: "RC-01")))
        game.add(.reactionAdded(.init(roundNumber: 1, seatId: game.seat(1), reaction: .skull)), actor: 1)
        #expect(game.state.receipts.count == 1)
        #expect(game.state.reactions[1]?[game.seat(1)] == .skull)
    }

    @Test("The finisher's rounds are authoritative; an unseen earlier edit is surfaced as late")
    func finishSnapshot() {
        var game = TestGame()
        game.setUp(planned: 1)
        game.record([3, 9, 7], knocker: 0)
        let original = game.state.rounds.map(\.round)
        let base = game.wallMs
        // Device B edited offline before the finish, but device A never saw it.
        let edit = game.add(.roundEdited(.init(round: game.round(1, [3, 9, 1], knocker: 0))), device: game.deviceB, at: base + 1_000, actor: 1)
        game.add(.gameFinished(.init(reason: .completed, finalRounds: original)), device: game.deviceA, at: base + 2_000)
        let state = game.state
        #expect(state.rounds.map(\.round) == original)
        #expect(state.lateOperations.map(\.id) == [edit.opId])
    }

    @Test("Abandon beats everything except a restore within 15 minutes")
    func abandonAndRestore() {
        var game = TestGame()
        game.setUp()
        game.record([3, 9, 7], knocker: 0)
        let abandonedAt = game.wallMs + 1_000
        game.add(.gameAbandoned(.init()), at: abandonedAt)
        game.record([3, 9, 7], knocker: 0) // ignored
        #expect(game.state.status == .abandoned)
        #expect(game.state.rounds.count == 1)
        #expect(game.state.lateOperations.first?.reason == .afterAbandon)

        var restored = game
        restored.add(.gameRestored(.init()), at: abandonedAt + 14 * 60_000)
        #expect(restored.state.status == .active)

        var expired = game
        expired.add(.gameRestored(.init()), at: abandonedAt + 16 * 60_000)
        #expect(expired.state.status == .abandoned)
    }

    @Test("GameConfigured changes the lobby's word, mode and cap, and is refused after Deal")
    func gameConfigured() {
        var lobby = TestGame()
        lobby.setUp(start: false)
        lobby.add(.gameConfigured(.init(tableWord: " Last Call ", scoringMode: .selfReport, houseVoiceCap: .clean)))
        #expect(lobby.state.config.tableWord == "Last Call")
        #expect(lobby.state.config.scoringMode == .selfReport)
        #expect(lobby.state.config.houseVoiceCap == .clean)
        lobby.add(.gameConfigured(.init(tableWord: "Last Call", scoringMode: .scorekeeper, houseVoiceCap: nil)))
        #expect(lobby.state.config.houseVoiceCap == nil)

        var dealt = TestGame()
        dealt.setUp()
        let word = dealt.state.config.tableWord
        dealt.add(.gameConfigured(.init(tableWord: "Too Late", scoringMode: .selfReport, houseVoiceCap: nil)))
        #expect(dealt.state.config.tableWord == word)
        #expect(dealt.state.lateOperations.last?.reason == .afterDeal)
    }

    @Test("A table holds at most 8")
    func tableFull() {
        let latecomer = Seat(player: .guest(GuestID()), displayName: "Late", order: 9)
        var big = TestGame(players: 8)
        big.setUp(start: false)
        big.add(.playerSeated(.init(seat: latecomer)))
        #expect(big.state.seats.count == 8)
        #expect(big.state.lateOperations.last?.reason == .tableFull)
    }

    @Test("A late joiner plays from the next round at the highest total, last in the deal")
    func lateJoin() {
        var game = TestGame()
        game.setUp()
        game.record([3, 9, 7], knocker: 0) // totals −10, 9, 7
        // A phone can't pick its own starting score or round.
        var latecomer = Seat(player: .guest(GuestID()), displayName: "Late", order: 0)
        latecomer.joinedRound = 1
        latecomer.startingScore = -50
        game.add(.playerSeated(.init(seat: latecomer)))

        let state = game.state
        let joined = state.seat(latecomer.id)
        #expect(state.seats.count == 4)
        #expect(joined?.joinedRound == 2)
        #expect(joined?.startingScore == 9)
        #expect(state.seats.last?.id == latecomer.id)
        #expect(state.standing(for: latecomer.id)?.total == 9)
        #expect(state.audit.last?.change == .lateJoin(seat: latecomer.id, round: 2, startingScore: 9))
        // Whoever was about to deal still does, and the joiner deals after the old last seat.
        #expect(state.currentDealer == game.seat(1))

        // Round 2 needs the joiner's hand.
        game.record([3, 9, 7], knocker: 0)
        #expect(game.state.rounds.count == 1)
        #expect(game.state.lateOperations.last?.reason == .invalid)
        var hands = game.round(2, [5, 9, 7], knocker: 0).hands
        hands[latecomer.id] = 4
        game.add(.roundRecorded(.init(round: Round(number: 2, hands: hands, knocker: game.seat(0)))))
        #expect(game.state.rounds.count == 2)
        #expect(game.state.standing(for: latecomer.id)?.total == 13)
        #expect(game.state.currentDealer == game.seat(2))
    }

    @Test("A late joiner can be removed until they've played, and blocks undoing the round before")
    func lateJoinUndoAndRemove() {
        var game = TestGame()
        game.setUp()
        game.record([3, 9, 7], knocker: 0)
        let latecomer = Seat(player: .guest(GuestID()), displayName: "Late", order: 9)
        game.add(.playerSeated(.init(seat: latecomer)))

        game.add(.roundUndone(.init(roundNumber: 1)))
        #expect(game.state.rounds.count == 1)
        #expect(game.state.lateOperations.last?.reason == .seatsLocked)

        var removed = game
        removed.add(.seatRemoved(.init(seatId: latecomer.id)))
        #expect(removed.state.seats.count == 3)
        #expect(removed.state.currentDealer == game.seat(1))

        var hands = game.round(2, [5, 9, 7], knocker: 0).hands
        hands[latecomer.id] = 4
        game.add(.roundRecorded(.init(round: Round(number: 2, hands: hands, knocker: game.seat(0)))))
        game.add(.seatRemoved(.init(seatId: latecomer.id)))
        #expect(game.state.seats.count == 4)
        #expect(game.state.lateOperations.last?.reason == .seatsLocked)
        // Editing a round from before they sat down doesn't need their hand.
        game.add(.roundEdited(.init(round: game.round(1, [3, 9, 8], knocker: 0))))
        #expect(game.state.rounds[0].round.hands[game.seat(2)] == 8)
    }

    @Test("An inherent knock: −10 if lowest alone, otherwise 0, never +10; tracked apart from knocks")
    func inherentKnock() {
        var game = TestGame()
        game.setUp()
        game.add(.roundRecorded(.init(round: Round(number: 1, hands: game.round(1, [0, 3, 7], knocker: 0).hands, knocker: game.seat(0), isInherent: true))))
        game.add(.roundRecorded(.init(round: Round(number: 2, hands: game.round(2, [0, -2, 7], knocker: 0).hands, knocker: game.seat(0), isInherent: true))))
        game.add(.roundRecorded(.init(round: Round(number: 3, hands: game.round(3, [0, 0, 7], knocker: 0).hands, knocker: game.seat(0), isInherent: true))))
        let state = game.state
        #expect(state.rounds.map { $0.scores[game.seat(0)] } == [-10, 0, 0])
        #expect(state.rounds.map(\.outcome) == [.landed, .noPenalty, .tied])

        // Inherent needs the knocker's own hand of 0.
        game.add(.roundRecorded(.init(round: Round(number: 4, hands: game.round(4, [5, 3, 7], knocker: 0).hands, knocker: game.seat(0), isInherent: true))))
        #expect(game.state.rounds.count == 3)
        #expect(game.state.lateOperations.last?.reason == .invalid)

        game.add(.gameFinished(.init(reason: .completed, finalRounds: game.state.rounds.map(\.round))))
        let stats = StatsSnapshot.build([game.state]).stats(for: game.seats[0].player)
        #expect(stats?.knocks == 0)
        #expect(stats?.inherentKnocks == 3)
        #expect(stats?.inherentKnocksLanded == 1)
    }

    @Test("Saved scores and missing knockers are refused outside imported games")
    func importedRoundsOnly() {
        let hands: (TestGame) -> [SeatID: Int] = { $0.round(1, [4, 5, -1], knocker: 0).hands }
        var live = TestGame()
        live.setUp()
        live.add(.roundRecorded(.init(round: Round(number: 1, hands: hands(live), knocker: nil, inherent: nil, recordedScores: hands(live)))))
        #expect(live.state.rounds.isEmpty)

        var imported = TestGame()
        imported.add(.gameCreated(.init(config: GameConfig(plannedRounds: 3, tableWord: "Legacy", imported: true), host: imported.seat(0))))
        for seat in imported.seats { imported.add(.playerSeated(.init(seat: seat))) }
        imported.add(.gameStarted(.init(seatOrder: imported.seats.map(\.id), firstDealer: imported.seat(0))))
        // The web marked a tie though the knocker was lowest alone: the saved scores stand.
        var tied = Round(number: 1, hands: imported.round(1, [0, 6, 8], knocker: 0).hands, knocker: imported.seat(0), inherent: nil, recordedScores: [:])
        tied.recordedScores = tied.hands
        imported.add(.roundRecorded(.init(round: tied)))
        imported.add(.roundRecorded(.init(round: Round(number: 2, hands: hands(imported), knocker: nil, inherent: nil, recordedScores: hands(imported)))))
        let state = imported.state
        #expect(state.rounds.count == 2)
        #expect(state.rounds[0].scores[imported.seat(0)] == 0)
        #expect(state.rounds[0].outcome == .tied)
        #expect(state.rounds[1].knocker == nil)
        #expect(state.rounds[1].outcome == nil)
        #expect(state.totals[imported.seat(2)] == 8 - 1)
    }

    @Test("Only games with 3+ rounds count for stats")
    func countedGames() {
        var short = TestGame()
        short.setUp()
        short.record([3, 9, 7], knocker: 0)
        short.record([3, 9, 7], knocker: 0)
        short.add(.gameFinished(.init(reason: .endedEarly, finalRounds: short.state.rounds.map(\.round))))
        #expect(short.state.status == .finished)
        #expect(!short.state.countsForStats)

        var full = TestGame()
        full.setUp()
        full.record([3, 9, 7], knocker: 0)
        full.record([3, 9, 7], knocker: 0)
        // Joins for Round 3 only: under 3 rounds played, so left out of this game's stats.
        let latecomer = Seat(player: .guest(GuestID()), displayName: "Late", order: 9)
        full.add(.playerSeated(.init(seat: latecomer)))
        var hands = full.round(3, [3, 9, 7], knocker: 0).hands
        hands[latecomer.id] = 4
        full.add(.roundRecorded(.init(round: Round(number: 3, hands: hands, knocker: full.seat(0)))))
        full.add(.gameFinished(.init(reason: .completed, finalRounds: full.state.rounds.map(\.round))))
        #expect(full.state.countsForStats)

        let snapshot = StatsSnapshot.build([short.state, full.state])
        #expect(snapshot.games.map(\.id) == [full.gameID])
        #expect(snapshot.games.first?.participants.count == 3)
        #expect(snapshot.games.first?.contains(latecomer.player) == false)
        #expect(snapshot.games.first?.totals[full.seats[0].player] == full.state.standing(for: full.seat(0))?.total)
    }

    @Test("A phone taking over a seat after the start is logged")
    func seatLinked() {
        var game = TestGame()
        game.setUp()
        var seat = game.seats[2]
        seat.deviceID = game.deviceB
        game.add(.playerSeated(.init(seat: seat)), device: game.deviceB, actor: nil)
        #expect(game.state.seat(game.seat(2))?.deviceID == game.deviceB)
        #expect(game.state.audit.last?.change == .seatLinked(seat: game.seat(2)))
    }

    @Test("Only the latest round can be undone")
    func undoOnlyLatest() {
        var game = TestGame()
        game.setUp()
        game.record([3, 9, 7], knocker: 0)
        game.record([3, 9, 7], knocker: 0)
        game.add(.roundUndone(.init(roundNumber: 1)))
        #expect(game.state.rounds.count == 2)
        #expect(game.state.lateOperations.last?.reason == .notLatestRound)
    }

    @Test("Live knock: pre-fill, clear, override logged")
    func liveKnock() {
        var game = TestGame()
        game.setUp()
        game.add(.knockMarked(.init(roundNumber: 1, knocker: game.seat(2))), actor: 1)
        #expect(game.state.liveKnock?.knocker == game.seat(2))
        #expect(game.state.liveKnock?.markedByName == "P1")
        game.add(.knockMarked(.init(roundNumber: 1, knocker: nil)))
        #expect(game.state.liveKnock == nil)
        game.add(.knockMarked(.init(roundNumber: 1, knocker: game.seat(2))))
        game.record([3, 9, 7], knocker: 0)
        #expect(game.state.liveKnock == nil)
        #expect(game.state.audit.contains { $0.change == .knockerOverridden(round: 1, marked: game.seat(2), recorded: game.seat(0)) })
    }

    @Test("Self-report: the round completes when everyone has reported and one knocked")
    func selfReport() {
        var game = TestGame()
        game.setUp(mode: .selfReport)
        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(0), hand: 3, knocked: true)))
        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(1), hand: 9, knocked: false)))
        #expect(game.state.selfReport?.waitingOn == [game.seat(2)])
        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(2), hand: 7, knocked: false)))
        #expect(game.state.rounds.count == 1)
        #expect(game.state.rounds[0].scores[game.seat(0)] == -10)
        #expect(game.state.rounds[0].recordedBy == "Everyone reported")
        #expect(game.state.selfReport == nil)
    }

    @Test("Self-report: two claimed knockers need a decision")
    func selfReportConflict() {
        var game = TestGame()
        game.setUp(mode: .selfReport)
        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(0), hand: 3, knocked: true)))
        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(1), hand: 2, knocked: true)))
        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(2), hand: 7, knocked: false)))
        #expect(game.state.rounds.isEmpty)
        #expect(game.state.selfReport?.needsKnockerDecision == true)
        game.add(.knockerProposed(.init(roundNumber: 1, knocker: game.seat(1))), actor: 2)
        #expect(game.state.selfReport?.proposals.first?.knocker == game.seat(1))
        game.add(.knockerResolved(.init(roundNumber: 1, knocker: game.seat(1))))
        #expect(game.state.rounds.count == 1)
        #expect(game.state.rounds[0].knocker == game.seat(1))
        #expect(game.state.rounds[0].outcome == .landed)
    }

    @Test("Invalid rounds are refused")
    func invalidRound() {
        var game = TestGame()
        game.setUp()
        let missingHand = Round(number: 1, hands: [game.seat(0): 3, game.seat(1): 4], knocker: game.seat(0))
        game.add(.roundRecorded(.init(round: missingHand)))
        let badRange = game.round(1, [3, 1000, 4], knocker: 0)
        game.add(.roundRecorded(.init(round: badRange)))
        #expect(game.state.rounds.isEmpty)
        #expect(game.state.lateOperations.map(\.reason) == [.invalid, .invalid])
    }

    @Test("Taunts, retraction and the feed")
    func tauntsAndFeed() {
        var game = TestGame()
        game.setUp()
        let tauntID = UUID()
        game.add(.tauntSent(.init(tauntId: tauntID, roundNumber: 1, from: game.seat(1), fromName: "P1", target: .seat(game.seat(0)), content: .custom(text: "nope"))), actor: 1)
        game.record([3, 9, 7], knocker: 0)
        #expect(game.state.visibleTaunts.count == 1)
        #expect(game.state.feed.count == 2)
        game.add(.tauntRetracted(.init(tauntId: tauntID, reason: "filter")))
        #expect(game.state.visibleTaunts.isEmpty)
        #expect(game.state.feed.count == 1)
    }

    @Test("House voice is the lowest seated level, lowered further by the cap")
    func houseVoice() {
        var game = TestGame()
        game.add(.gameCreated(.init(config: GameConfig(tableWord: "Cold Deck", houseVoiceCap: nil), host: game.seat(0))))
        for (index, level) in [LanguageLevel.unhinged, .spicy, .unhinged].enumerated() {
            var seat = game.seats[index]
            seat.languageLevel = level
            game.add(.playerSeated(.init(seat: seat)))
        }
        #expect(game.state.houseLevel == .spicy)
        #expect(Voice.house(for: game.state, viewer: .clean).level == .clean)
        #expect(LanguageLevel.house(seated: [.unhinged], cap: .clean) == .clean)
        #expect(LanguageLevel.house(seated: []) == .unhinged)
    }
}
