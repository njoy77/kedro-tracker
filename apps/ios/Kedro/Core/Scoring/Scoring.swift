import Foundation

/// The canonical Cambio scoring rules (PRD §2.6, §2.7). Pure functions, identical on every device
/// and mirrored on the server (`packages/shared`). Generic over the key so stats code can score
/// by `SeatID`, `PlayerRef` or anything else hashable.
nonisolated enum Scoring {
    /// What a knocker scores when their hand is strictly lowest.
    static let landedScore = -10
    /// What a beaten knocker adds to their hand.
    static let failedPenalty = 10

    /// The knock outcome, or nil if the knocker has no hand.
    ///
    /// - strictly lowest → `.landed`
    /// - tied for lowest → `.tied`
    /// - someone lower → `.failed`, or `.noPenalty` for an inherent knock (it never takes +10)
    static func knockOutcome<Key: Hashable>(hands: [Key: Int], knocker: Key, inherent: Bool = false) -> KnockOutcome? {
        guard let knockerHand = hands[knocker] else { return nil }
        guard let lowestOther = hands.lazy.filter({ $0.key != knocker }).map(\.value).min() else {
            return .landed
        }
        if knockerHand < lowestOther { return .landed }
        if knockerHand == lowestOther { return .tied }
        return inherent ? .noPenalty : .failed
    }

    /// Round scores from hand values and the knocker (PRD §2.6):
    ///
    /// | Situation | Knocker | Everyone else |
    /// |---|---|---|
    /// | Knocker strictly lowest | −10 flat | hand |
    /// | Knocker tied for lowest | hand | hand |
    /// | Someone lower | hand + 10 (inherent knock: hand, 0) | hand |
    ///
    /// If the knocker has no hand (an invalid round), the hands are returned unchanged.
    static func roundScores<Key: Hashable>(hands: [Key: Int], knocker: Key, inherent: Bool = false) -> [Key: Int] {
        var scores = hands
        guard let knockerHand = hands[knocker], let outcome = knockOutcome(hands: hands, knocker: knocker, inherent: inherent) else {
            return scores
        }
        scores[knocker] = knockerScore(hand: knockerHand, outcome: outcome)
        return scores
    }

    /// What the knocker scores for a hand and outcome.
    static func knockerScore(hand: Int, outcome: KnockOutcome) -> Int {
        switch outcome {
        case .landed: landedScore
        case .tied, .noPenalty: hand
        case .failed: hand + failedPenalty
        }
    }

    /// Cumulative totals: the sum of each key's round scores. Keys missing from a round add 0.
    static func totals<Key: Hashable>(_ roundScores: [[Key: Int]]) -> [Key: Int] {
        var totals: [Key: Int] = [:]
        for scores in roundScores {
            for (key, score) in scores {
                totals[key, default: 0] += score
            }
        }
        return totals
    }

    /// Standard competition ranking, lowest total first: totals 26, 29, 29, 44 rank 1, 2=, 2=, 4.
    static func ranks<Key: Hashable>(_ totals: [Key: Int]) -> [Key: Rank] {
        let counts = Dictionary(grouping: totals.values, by: { $0 }).mapValues(\.count)
        var ranks: [Key: Rank] = [:]
        for (key, total) in totals {
            let better = totals.values.lazy.filter { $0 < total }.count
            ranks[key] = Rank(position: better + 1, isShared: (counts[total] ?? 0) > 1)
        }
        return ranks
    }

    /// Everyone with the lowest total. Ties share the win (PRD §2.7).
    static func winners<Key: Hashable>(_ totals: [Key: Int]) -> Set<Key> {
        guard let best = totals.values.min() else { return [] }
        return Set(totals.filter { $0.value == best }.keys)
    }

    /// Keys ordered best first; equal totals keep the order of `tieOrder` (e.g. seat order).
    static func ordered<Key: Hashable>(_ totals: [Key: Int], tieOrder: [Key]) -> [Key] {
        let position = Dictionary(tieOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return totals.keys.sorted { lhs, rhs in
            let left = totals[lhs] ?? 0, right = totals[rhs] ?? 0
            if left != right { return left < right }
            return (position[lhs] ?? .max) < (position[rhs] ?? .max)
        }
    }
}

/// A finishing or standings position. `isShared` renders as "2=" (design §6.1).
nonisolated struct Rank: Hashable, Sendable, Codable, Comparable {
    var position: Int
    var isShared: Bool

    /// "1", "2=".
    var label: String { isShared ? "\(position)=" : "\(position)" }

    /// "1st", "2nd", "3rd", "4th" (for the mini bar and Live Activity).
    var ordinal: String {
        let suffix: String
        switch (position % 10, position % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(position)\(suffix)"
    }

    static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.position < rhs.position }
}
