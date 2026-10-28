import Foundation

/// The result of a knock (PRD §2.6, design §3.6). JSON: `"landed"` | `"tied"` | `"failed"`.
nonisolated enum KnockOutcome: String, Hashable, Sendable, Codable, CaseIterable {
    /// Knocker had the strictly lowest hand: −10 flat.
    case landed
    /// Knocker tied for the lowest hand: scores their hand.
    case tied
    /// Someone had a lower hand: knocker scores hand + 10.
    case failed

    /// The literal outcome word (design §3.6), identical in every language level.
    var word: String { rawValue }

    /// SF Symbol for the outcome glyph: ✓ / = / ✗.
    var systemImage: String {
        switch self {
        case .landed: "checkmark"
        case .tied: "equal"
        case .failed: "xmark"
        }
    }
}

/// One round's inputs: every seat's hand value and who knocked. Scores are derived, never stored
/// (`Scoring.roundScores`).
///
/// JSON: `{"number":5,"hands":{"p:…":2,"p:…":9,"g:…":4},"knocker":"p:…"}`
nonisolated struct Round: Hashable, Sendable, Codable {
    /// Hands below −2 are impossible (two red Kings are the only negative cards); there's no real
    /// upper limit, but the pad stops at 999 (design §7.1).
    static let handRange = -2...999

    /// 1-based.
    var number: Int
    var hands: [SeatID: Int]
    var knocker: SeatID

    init(number: Int, hands: [SeatID: Int], knocker: SeatID) {
        self.number = number
        self.hands = hands
        self.knocker = knocker
    }

    /// Round scores after the knock adjustment.
    var scores: [SeatID: Int] { Scoring.roundScores(hands: hands, knocker: knocker) }

    /// nil only if the knocker has no hand recorded (an invalid round).
    var outcome: KnockOutcome? { Scoring.knockOutcome(hands: hands, knocker: knocker) }

    /// The knocker's hand value.
    var knockerHand: Int? { hands[knocker] }

    /// The lowest hand among everyone except the knocker.
    var lowestOtherHand: Int? { hands.filter { $0.key != knocker }.values.min() }

    /// The non-knocker with the lowest hand (ties broken by seat ID for determinism).
    var lowestOtherSeat: SeatID? {
        hands.filter { $0.key != knocker }.min { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }

    /// True when every hand is in range and the knocker has a hand.
    var isValid: Bool {
        hands[knocker] != nil && hands.values.allSatisfy(Self.handRange.contains)
    }
}
