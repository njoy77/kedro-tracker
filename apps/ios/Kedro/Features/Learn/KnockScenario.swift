import Foundation

/// A round to learn from: players' cards face up and who knocked (the knock-gamble quiz and the
/// Score a Round drill, design §13.1). Scored with `Scoring`, exactly like a real round.
nonisolated struct KnockScenario: Hashable, Sendable, Identifiable {
    nonisolated struct Player: Hashable, Sendable, Identifiable {
        var name: String
        var cards: [PlayingCard]
        var id: String { name }
        var hand: Int { PlayingCard.handValue(cards) }
    }

    var id: String
    var players: [Player]
    var knockerIndex: Int

    var knocker: Player { players[knockerIndex] }

    private var hands: [String: Int] { Dictionary(uniqueKeysWithValues: players.map { ($0.name, $0.hand) }) }

    var outcome: KnockOutcome? { Scoring.knockOutcome(hands: hands, knocker: knocker.name) }

    var scores: [String: Int] { Scoring.roundScores(hands: hands, knocker: knocker.name) }

    var knockerScore: Int { scores[knocker.name] ?? knocker.hand }

    /// The three possible knocker scores, in a fixed order (−10, the hand, the hand + 10).
    var choices: [Int] {
        var seen = Set<Int>()
        return [Scoring.landedScore, knocker.hand, knocker.hand + Scoring.failedPenalty].filter { seen.insert($0).inserted }
    }

    /// The literal verdict ("Failed: 6 + 10 = 16.").
    var verdict: String {
        outcome.map { Literal.verdict($0, hand: knocker.hand) } ?? ""
    }

    /// Why (literal), reusing the Knock Calculator's wording.
    var explanation: String {
        KnockCalculator.make(players.map { ($0.name, $0.hand) }, knockerIndex: knockerIndex).explanation ?? ""
    }
}

extension KnockScenario {
    /// One of each outcome, small enough to add up at a glance.
    static let landed = KnockScenario(id: "landed", players: [
        Player(name: "Ana", cards: [.card(.ace, .spades), .card(.number(2), .clubs), .card(.king, .hearts), .card(.number(2), .diamonds)]),
        Player(name: "Ben", cards: [.card(.number(3), .clubs), .card(.number(4), .hearts)]),
        Player(name: "Cleo", cards: [.card(.number(9), .spades), .joker]),
    ], knockerIndex: 0)

    static let tied = KnockScenario(id: "tied", players: [
        Player(name: "Ana", cards: [.joker, .card(.number(4), .clubs)]),
        Player(name: "Ben", cards: [.card(.number(2), .spades), .card(.number(2), .hearts)]),
        Player(name: "Cleo", cards: [.card(.number(5), .diamonds), .card(.number(4), .spades)]),
    ], knockerIndex: 1)

    static let failed = KnockScenario(id: "failed", players: [
        Player(name: "Ana", cards: [.card(.king, .diamonds), .card(.number(4), .clubs)]),
        Player(name: "Ben", cards: [.card(.number(9), .clubs)]),
        Player(name: "Cleo", cards: [.card(.number(3), .spades), .card(.number(3), .hearts)]),
    ], knockerIndex: 2)

    /// Two cards can hide a black King; a red King can force a tie.
    static let redKing = KnockScenario(id: "redKing", players: [
        Player(name: "Ana", cards: [.card(.number(5), .hearts), .card(.number(6), .clubs)]),
        Player(name: "Ben", cards: [.card(.king, .spades), .card(.ace, .hearts)]),
        Player(name: "Cleo", cards: [.card(.queen, .diamonds), .card(.king, .hearts)]),
        Player(name: "Dev", cards: [.card(.number(8), .spades), .card(.number(7), .diamonds)]),
    ], knockerIndex: 0)

    static let drill: [KnockScenario] = [.landed, .tied, .failed, .redKing]
    static let quiz: [KnockScenario] = [.failed, .landed, .tied]
}
