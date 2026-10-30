import Foundation
import Testing
@testable import Kedro

@Suite("Table links and invite tokens")
struct TableInviteLinkTests {
    @Test("Links round-trip through their URL")
    func roundTrip() throws {
        let game = GameID()
        let invite = TableInviteLink(kind: .table, gameID: game, token: "abc123")
        #expect(invite.url.absoluteString == "https://kedro.app/t/\(game.uuidString)?k=abc123")
        #expect(TableInviteLink(url: invite.url) == invite)

        let saved = TableInviteLink(kind: .savedSeat, gameID: game, hostName: "Maya", tableWord: "Cold Deck")
        let parsed = try #require(TableInviteLink(url: saved.url))
        #expect(parsed.kind == .savedSeat)
        #expect(parsed.hostName == "Maya")
        #expect(parsed.tableWord == "Cold Deck")
    }

    @Test("The custom scheme works too; anything else doesn't")
    func schemes() throws {
        let game = GameID()
        let custom = try #require(URL(string: "kedro://t/\(game.uuidString)?k=x"))
        #expect(TableInviteLink(url: custom)?.gameID == game)
        for string in ["https://example.com/t/\(game.uuidString)", "https://kedro.app/x/\(game.uuidString)", "https://kedro.app/t/not-a-uuid", "https://kedro.app/t"] {
            let url = try #require(URL(string: string))
            #expect(TableInviteLink(url: url) == nil, "\(string)")
        }
    }

    @Test("The token rotates every minute and accepts the previous window")
    func rotation() {
        let token = RotatingTableToken(gameID: GameID())
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let now = token.token(at: start)
        #expect(now.count == 16)
        #expect(token.isValid(now, at: start))
        #expect(token.isValid(now, at: start.addingTimeInterval(60)))
        #expect(!token.isValid(now, at: start.addingTimeInterval(125)))
        #expect(token.token(at: start.addingTimeInterval(60)) != now)
        #expect(RotatingTableToken(gameID: token.gameID).token(at: start) != now) // per-table secret
        #expect(RotatingTableToken.nextRotation(after: start) > start)
    }

    @Test("QR codes encode")
    func qr() {
        #expect(QRCode.image(for: TableInviteLink(gameID: GameID(), token: "abc").url.absoluteString) != nil)
    }
}

@Suite("Table card")
struct TableCardTests {
    @Test("Sit Down, Ask to Sit or Watch", arguments: [
        (true, false, false, SitDownAction.sitDown),
        (false, false, false, .askToSit),
        (false, true, false, .sitDown),
        (true, false, true, .watch),
        (false, false, true, .watch),
        (false, true, true, .sitDown),
    ])
    func action(playedWith: Bool, savedSeat: Bool, locked: Bool, expected: SitDownAction) {
        #expect(SitDownAction.action(isPlayedWith: playedWith, hasSavedSeat: savedSeat, seatsLocked: locked) == expected)
    }

    @Test("The card's lines read like mockup frame 4")
    func lines() {
        let table = NearbyTable(
            id: GameID(), host: PreviewData.maya, tableWord: "Last Call", distance: 0.6,
            seatedPlayers: [PreviewData.maya, PreviewData.theo, PreviewData.priya], guestCount: 1,
            isPlayedWith: true, roundsPlayed: 0
        )
        let card = TableCardContent(table: table)
        #expect(card.title == "Maya's Table")
        #expect(card.locationLine == "Last Call · At your table · 0.6 m")
        #expect(card.seatedLine.hasSuffix("+ 1 guest"))
        #expect(card.action == .sitDown)
    }

    @Test("Join with Code matches table words loosely")
    func tableWords() {
        #expect(TableWord.normalized("  cold   DECK ") == TableWord.normalized("Cold Deck"))
    }
}

@Suite("Claim codes")
struct ClaimCodeTests {
    @Test("Codes come from bare codes and claim links", arguments: [
        ("ABC-123-XYZ", "ABC-123-XYZ"),
        ("https://kedro.app/claim/abc123def", "abc123def"),
        ("https://kedro.app/claim?code=zz99zz", "zz99zz"),
        ("  abcdef  ", "abcdef"),
    ])
    func parses(input: String, expected: String) {
        #expect(PendingClaims.code(from: input) == expected)
    }

    @Test("Junk isn't a code", arguments: ["", "abc", "has spaces in it", "emoji🦊code"])
    func rejects(input: String) {
        #expect(PendingClaims.code(from: input) == nil)
    }
}

@Suite("Play insights")
struct PlayInsightsTests {
    private var history: [GameState] {
        let byGame = Dictionary(grouping: PreviewData.historyOperations, by: \.gameId)
        return byGame.map { GameState.fold($0.value, gameID: $0.key) }
    }

    @Test("Stakes never come back empty")
    func stakesFallback() {
        #expect(PlayInsights.stakes(for: .player(PlayerID()), in: history) == [.nothing])
    }

    @Test("Rivalries count shared finished games from both sides")
    func rivalries() {
        let games = history
        let mine = PlayInsights.rivalries(for: PreviewData.noah.ref, in: games)
        let ana = PlayInsights.rivalries(for: PreviewData.ana.ref, in: games)
        if let noahVsAna = mine[PreviewData.ana.ref], let anaVsNoah = ana[PreviewData.noah.ref] {
            #expect(noahVsAna.mine == anaVsNoah.theirs)
            #expect(noahVsAna.theirs == anaVsNoah.mine)
            #expect(noahVsAna.gamesTogether == anaVsNoah.gamesTogether)
        }
        #expect(PlayInsights.gamesPlayed(by: PreviewData.noah.ref, in: games) > 0)
    }

    @Test("The digest shows your latest game when you've never looked")
    func digest() {
        let items = PlayInsights.digest(for: PreviewData.noah.ref, in: history, since: nil)
        #expect(items.count == 1)
        if case .lastGame = items.first {} else { Issue.record("Expected the last game first") }
        #expect(PlayInsights.digest(for: PreviewData.noah.ref, in: history, since: .distantFuture).isEmpty)
    }
}

@Suite("Learning")
struct LearningTests {
    @Test("Card values follow PRD §2.2")
    func values() {
        #expect(PlayingCard.card(.ace, .spades).value == 1)
        #expect(PlayingCard.card(.number(7), .hearts).value == 7)
        #expect(PlayingCard.card(.jack, .clubs).value == 11)
        #expect(PlayingCard.card(.queen, .diamonds).value == 12)
        #expect(PlayingCard.card(.king, .spades).value == 13)
        #expect(PlayingCard.card(.king, .clubs).value == 13)
        #expect(PlayingCard.card(.king, .hearts).value == -1)
        #expect(PlayingCard.card(.king, .diamonds).value == -1)
        #expect(PlayingCard.joker.value == 0)
    }

    @Test("The drill covers landed, tied, failed and going out")
    func drillOutcomes() {
        #expect(KnockScenario.landed.outcome == .landed)
        #expect(KnockScenario.landed.knockerScore == -10)
        #expect(KnockScenario.tied.outcome == .tied)
        #expect(KnockScenario.tied.knockerScore == 4)
        #expect(KnockScenario.failed.outcome == .failed)
        #expect(KnockScenario.failed.knockerScore == 16)
        #expect(KnockScenario.wentOut.outcome == .landed)
        #expect(KnockScenario.wentOut.knockerScore == -10)
        #expect(KnockScenario.wentOutBeaten.outcome == .noPenalty)
        #expect(KnockScenario.wentOutBeaten.knockerScore == 0, "going out never takes the +10")
        #expect(KnockScenario.wentOutBeaten.choices == [-10, 0, 10])
        #expect(KnockScenario.wentOutBeaten.verdict == "No penalty: 0.")
        #expect(Set(KnockScenario.drill.compactMap(\.outcome)) == [.landed, .tied, .failed, .noPenalty])
        #expect(KnockScenario.drill.contains { $0.inherent } && KnockScenario.quiz.contains { $0.inherent })
        for scenario in KnockScenario.drill + KnockScenario.quiz where scenario.inherent {
            #expect(scenario.knocker.cards.isEmpty && scenario.knocker.hand == 0)
        }
        for scenario in KnockScenario.drill + KnockScenario.quiz {
            #expect(scenario.choices.contains(scenario.knockerScore))
            #expect(!scenario.explanation.isEmpty)
        }
    }

    @Test("The Knock Calculator matches the PRD's worked examples")
    func calculator() {
        let failed = KnockCalculator.example
        #expect(failed.outcome == .failed)
        #expect(failed.entries.map { failed.scores[$0.id] } == [16, 3, 9])
        #expect(failed.verdict == "Failed: 6 + 10 = 16.")
        #expect(failed.explanation?.contains("Ana") == true)

        let landed = KnockCalculator.make([("A", 4), ("B", 7), ("C", 9)], knockerIndex: 0)
        #expect(landed.entries.map { landed.scores[$0.id] } == [-10, 7, 9])
        let tied = KnockCalculator.make([("A", 4), ("B", 4), ("C", 9)], knockerIndex: 0)
        #expect(tied.entries.map { tied.scores[$0.id] } == [4, 4, 9])
        #expect(tied.verdict == "Tied: 4.")
    }

    @Test("The Knock Calculator scores inherent knocks: −10 if lowest alone, otherwise 0, never +10")
    func calculatorInherent() throws {
        // The PRD's inherent examples: A 0, B 3 → −10; A 0, B 0 → 0; A 0, B −2 → 0.
        let outcomes = [3, 0, -2].map { other in
            KnockCalculator.make([("A", 0), ("B", other), ("C", 9)], knockerIndex: 0, inherent: true)
        }
        #expect(outcomes.map(\.outcome) == [.landed, .tied, .noPenalty])
        #expect(outcomes.map { $0.scores[$0.knocker] } == [-10, 0, 0])
        #expect(outcomes[2].verdict == "No penalty: 0.")
        #expect(outcomes[2].knockLine == "A went out with all four cards.")
        #expect(outcomes.allSatisfy { $0.explanation?.contains("all four cards") == true })

        // Turning it on zeroes the knocker's hand; another hand or another knocker turns it off.
        var calculator = KnockCalculator.example // Noah 6, Ana 3, Ben 9
        calculator.inherent = true
        #expect(calculator.knockerEntry?.hand == 0)
        #expect(calculator.outcome == .landed, "Noah's 0 now beats Ana's 3")
        let index = try #require(calculator.entries.firstIndex { $0.id == calculator.knocker })
        calculator.entries[index].hand = 5
        #expect(!calculator.inherent)
        calculator.inherent = true
        calculator.knocker = calculator.entries[1].id
        #expect(!calculator.inherent)

        // Every example in the menu is a valid round, and they cover every outcome.
        #expect(Set(KnockCalculator.examples.compactMap(\.calculator.outcome)) == Set(KnockOutcome.allCases))
    }

    @Test("Prefilling from an inherent round keeps it inherent")
    func prefillInherent() {
        let seats = [PreviewData.noahSeat, PreviewData.anaSeat, PreviewData.benSeat]
        let round = Round(number: 1, hands: [seats[0]: 0, seats[1]: -2, seats[2]: 9], knocker: seats[0], isInherent: true)
        let calculator = KnockCalculator(round: round, order: seats) { _ in nil }
        #expect(calculator.inherent)
        #expect(calculator.outcome == .noPenalty)
    }

    @Test("The calculator prefills from a round in seat order")
    func prefill() {
        let round = PreviewData.sampleRounds[4] // R5: Noah knocked on 2 and landed
        let state = PreviewData.sampleState(throughRound: 5)
        let calculator = KnockCalculator(round: round, order: state.seats.map(\.id)) { state.seat($0)?.displayName }
        #expect(calculator.entries.map(\.name) == ["Noah", "Ana", "Ben", "Cleo", "Sam"])
        #expect(calculator.entries.map(\.hand) == [2, 9, 6, 11, 4])
        #expect(calculator.knockerEntry?.name == "Noah")
        #expect(calculator.outcome == .landed)
    }

    @Test("The calculator keeps 3 to 8 players and always has a knocker")
    func editing() {
        var calculator = KnockCalculator.example
        calculator.remove(calculator.entries[0].id)
        #expect(calculator.entries.count == 3) // can't go below 3
        for _ in 0..<10 { calculator.addPlayer() }
        #expect(calculator.entries.count == 8)
        calculator.remove(calculator.knocker)
        #expect(calculator.entries.contains { $0.id == calculator.knocker })
    }

    @Test("Rules search finds rules by text and keyword")
    func rulesSearch() {
        #expect(RulesContent.search("").count == RulesContent.sections.count)
        let redKing = RulesContent.search("minus")
        #expect(redKing.flatMap(\.rules).contains { $0.id == "values.redKing" })
        #expect(RulesContent.search("zzzz").isEmpty)
        #expect(RulesContent.search("Sticking").first?.rules.count == 2)
        let inherent = RulesContent.search("went out").flatMap(\.rules).map(\.id)
        #expect(inherent.contains("knocking.inherent") && inherent.contains("scoring.inherent"))
    }
}
