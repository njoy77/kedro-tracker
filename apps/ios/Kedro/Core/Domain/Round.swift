import Foundation

/// The result of a knock (PRD §2.6, design §3.6). JSON: `"landed"` | `"tied"` | `"failed"` |
/// `"noPenalty"`.
nonisolated enum KnockOutcome: String, Hashable, Sendable, Codable, CaseIterable {
    /// Knocker had the strictly lowest hand: −10 flat.
    case landed
    /// Knocker tied for the lowest hand: scores their hand.
    case tied
    /// Someone had a lower hand: knocker scores hand + 10.
    case failed
    /// An inherent knock someone beat: the knocker scores their hand (0), never the +10.
    case noPenalty

    /// The literal outcome word (design §3.6), identical in every language level.
    var word: String { self == .noPenalty ? "no penalty" : rawValue }

    /// SF Symbol for the outcome glyph: ✓ / = / ✗.
    var systemImage: String {
        switch self {
        case .landed: "checkmark"
        case .tied: "equal"
        case .failed: "xmark"
        case .noPenalty: "minus"
        }
    }
}

/// One round's inputs: every seat's hand value and who knocked. Scores are derived, never stored
/// (`Scoring.roundScores`), except on rounds imported from the web app (games with
/// `GameConfig.imported`): those keep the web's saved `recordedScores` and may have no known
/// knocker. `inherent` is who went out with an inherent knock (played all four cards, hand 0);
/// in a live round it's always the knocker.
///
/// JSON: `{"number":5,"hands":{"p:…":2,"p:…":9,"g:…":4},"knocker":"p:…"}`, plus `"inherent"`
/// and (imported rounds only) `"scores"` when set.
nonisolated struct Round: Hashable, Sendable, Codable {
    /// Hands below −2 are impossible (two red Kings are the only negative cards); there's no real
    /// upper limit, but the pad stops at 999 (design §7.1).
    static let handRange = -2...999

    /// 1-based.
    var number: Int
    var hands: [SeatID: Int]
    /// Who knocked. Always set for live rounds; nil only on an imported round nobody recorded.
    var knocker: SeatID?
    /// Who went out with an inherent knock.
    var inherent: SeatID?
    /// Imported rounds only: the web app's saved scores, kept as they were.
    var recordedScores: [SeatID: Int]?

    private enum CodingKeys: String, CodingKey {
        case number, hands, knocker, inherent
        case recordedScores = "scores"
    }

    init(number: Int, hands: [SeatID: Int], knocker: SeatID, isInherent: Bool = false) {
        self.number = number
        self.hands = hands
        self.knocker = knocker
        inherent = isInherent ? knocker : nil
    }

    /// An imported round (tests and fixtures; the importer runs on the server).
    init(number: Int, hands: [SeatID: Int], knocker: SeatID?, inherent: SeatID?, recordedScores: [SeatID: Int]) {
        self.number = number
        self.hands = hands
        self.knocker = knocker
        self.inherent = inherent
        self.recordedScores = recordedScores
    }

    /// True when the knocker went out with an inherent knock (−10 if lowest alone, never +10).
    var isInherentKnock: Bool { knocker != nil && inherent == knocker }

    /// Round scores after the knock adjustment (an imported round's saved scores as they were).
    var scores: [SeatID: Int] {
        if let recordedScores { return recordedScores }
        guard let knocker else { return hands }
        return Scoring.roundScores(hands: hands, knocker: knocker, inherent: isInherentKnock)
    }

    /// nil without a knocker. For an imported round it's read from the saved knocker score.
    var outcome: KnockOutcome? {
        guard let knocker else { return nil }
        guard let recordedScores else { return Scoring.knockOutcome(hands: hands, knocker: knocker, inherent: isInherentKnock) }
        guard let score = recordedScores[knocker], let hand = hands[knocker] else { return nil }
        if score == Scoring.landedScore, hand != Scoring.landedScore { return .landed }
        if score == hand + Scoring.failedPenalty { return .failed }
        guard isInherentKnock, let lowest = lowestOtherHand, lowest < hand else { return .tied }
        return .noPenalty
    }

    /// The knocker's hand value.
    var knockerHand: Int? { knocker.flatMap { hands[$0] } }

    /// The lowest hand among everyone except the knocker.
    var lowestOtherHand: Int? { hands.filter { $0.key != knocker }.values.min() }

    /// The non-knocker with the lowest hand (ties broken by seat ID for determinism).
    var lowestOtherSeat: SeatID? {
        hands.filter { $0.key != knocker }.min { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }

    /// A live round: every hand in range, a knocker with a hand, an inherent knock only the
    /// knocker's own on a hand of 0, and no saved scores.
    var isValid: Bool { isValid(imported: false) }

    /// `imported`: the game came from the web importer, whose rounds may keep saved scores (for
    /// every seat with a hand) and have no knocker.
    func isValid(imported: Bool) -> Bool {
        guard hands.values.allSatisfy(Self.handRange.contains) else { return false }
        if let knocker, hands[knocker] == nil { return false }
        if let inherent, hands[inherent] == nil { return false }
        if imported { return recordedScores.map { Set($0.keys) == Set(hands.keys) } ?? true }
        guard recordedScores == nil, let knocker else { return false }
        if let inherent { return inherent == knocker && hands[knocker] == 0 }
        return true
    }
}
