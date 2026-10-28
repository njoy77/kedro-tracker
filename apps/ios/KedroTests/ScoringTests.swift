import Testing
@testable import Kedro

@Suite("Scoring (PRD §2.6)")
struct ScoringTests {
    @Test("PRD example: knocker strictly lowest scores −10 flat")
    func landed() {
        let scores = Scoring.roundScores(hands: ["A": 4, "B": 7, "C": 9], knocker: "A")
        #expect(scores == ["A": -10, "B": 7, "C": 9])
        #expect(Scoring.knockOutcome(hands: ["A": 4, "B": 7, "C": 9], knocker: "A") == .landed)
    }

    @Test("PRD example: knocker tied for lowest scores their hand")
    func tied() {
        let scores = Scoring.roundScores(hands: ["A": 4, "B": 4, "C": 9], knocker: "A")
        #expect(scores == ["A": 4, "B": 4, "C": 9])
        #expect(Scoring.knockOutcome(hands: ["A": 4, "B": 4, "C": 9], knocker: "A") == .tied)
    }

    @Test("PRD example: beaten knocker scores hand + 10")
    func failed() {
        let scores = Scoring.roundScores(hands: ["A": 6, "B": 3, "C": 9], knocker: "A")
        #expect(scores == ["A": 16, "B": 3, "C": 9])
        #expect(Scoring.knockOutcome(hands: ["A": 6, "B": 3, "C": 9], knocker: "A") == .failed)
    }

    @Test("8 players, knocker tied for lowest with one other: everyone scores their hand")
    func eightPlayerTiedKnock() {
        let hands = ["A": 3, "B": 9, "C": 3, "D": 12, "E": 7, "F": 15, "G": 4, "H": 21]
        #expect(Scoring.knockOutcome(hands: hands, knocker: "A") == .tied)
        #expect(Scoring.roundScores(hands: hands, knocker: "A") == hands)
    }

    @Test("8 players, knocker strictly lowest")
    func eightPlayerLanded() {
        let hands = ["A": 1, "B": 9, "C": 3, "D": 12, "E": 7, "F": 15, "G": 4, "H": 21]
        var expected = hands
        expected["A"] = -10
        #expect(Scoring.roundScores(hands: hands, knocker: "A") == expected)
    }

    @Test("Negative hands (red Kings)", arguments: [
        // (knocker hand, other hands, expected knocker score, outcome)
        (-2, [0, 5], -10, KnockOutcome.landed),
        (-1, [-1, 5], -1, .tied),
        (0, [-1, 5], 10, .failed),
        (-1, [-2, 3], 9, .failed),
        (2, [-1, 4], 12, .failed),
    ])
    func negativeHands(knocker: Int, others: [Int], expectedScore: Int, outcome: KnockOutcome) {
        var hands = ["K": knocker]
        for (index, hand) in others.enumerated() { hands["O\(index)"] = hand }
        #expect(Scoring.roundScores(hands: hands, knocker: "K")["K"] == expectedScore)
        #expect(Scoring.knockOutcome(hands: hands, knocker: "K") == outcome)
        // Everyone else always scores their own hand.
        for (index, hand) in others.enumerated() {
            #expect(Scoring.roundScores(hands: hands, knocker: "K")["O\(index)"] == hand)
        }
    }

    @Test("A knocker with no hand leaves the round unscored")
    func missingKnocker() {
        #expect(Scoring.knockOutcome(hands: ["A": 4], knocker: "Z") == nil)
        #expect(Scoring.roundScores(hands: ["A": 4], knocker: "Z") == ["A": 4])
    }

    @Test("Totals, shared ranks and shared wins")
    func ranksAndWinners() {
        let totals = Scoring.totals([["A": 10, "B": 20, "C": 20, "D": 5], ["A": 3, "B": -7, "C": 1, "D": 30]])
        #expect(totals == ["A": 13, "B": 13, "C": 21, "D": 35])
        let ranks = Scoring.ranks(totals)
        #expect(ranks["A"] == Rank(position: 1, isShared: true))
        #expect(ranks["B"] == Rank(position: 1, isShared: true))
        #expect(ranks["C"] == Rank(position: 3, isShared: false))
        #expect(ranks["D"]?.label == "4")
        #expect(ranks["A"]?.label == "1=")
        #expect(Scoring.winners(totals) == ["A", "B"])
        #expect(Scoring.ordered(totals, tieOrder: ["B", "A", "C", "D"]) == ["B", "A", "C", "D"])
    }

    @Test("Ordinals")
    func ordinals() {
        #expect([1, 2, 3, 4, 11, 12, 13, 21, 22].map { Rank(position: $0, isShared: false).ordinal }
            == ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd"])
    }

    @Test("Scores use a true minus")
    func trueMinus() {
        #expect(ScoreFormat.string(-10) == "\u{2212}10")
        #expect(ScoreFormat.signed(9) == "+9")
        #expect(ScoreFormat.signed(0) == "0")
        #expect(ScoreFormat.signed(-1) == "\u{2212}1")
    }
}
