import Foundation

/// The Knock Calculator's model (design §13.1): hands and a knocker in, every round score and the
/// reason out. Uses `Scoring` (PRD §2.6), so it can never disagree with the Table. Edits here never
/// touch a game.
nonisolated struct KnockCalculator: Hashable, Sendable {
    nonisolated struct Entry: Hashable, Sendable, Identifiable {
        let id: UUID
        var name: String
        var hand: Int

        init(id: UUID = UUID(), name: String, hand: Int) {
            self.id = id
            self.name = name
            self.hand = hand
        }
    }

    static let playerRange = GameConfig.seatRange

    var entries: [Entry]
    var knocker: UUID

    init(entries: [Entry], knocker: UUID? = nil) {
        self.entries = entries
        self.knocker = knocker ?? entries.first?.id ?? UUID()
    }

    /// The PRD's third worked example: the knocker is beaten (A 6, B 3, C 9).
    static let example = KnockCalculator.make([("Noah", 6), ("Ana", 3), ("Ben", 9)], knockerIndex: 0)

    static func make(_ players: [(String, Int)], knockerIndex: Int) -> KnockCalculator {
        let entries = players.map { Entry(name: $0.0, hand: $0.1) }
        let index = entries.indices.contains(knockerIndex) ? knockerIndex : 0
        return KnockCalculator(entries: entries, knocker: entries.isEmpty ? nil : entries[index].id)
    }

    /// Prefills from a recorded round, naming seats with `name` (seats keep their clockwise
    /// order when `order` is given).
    init(round: Round, order: [SeatID] = [], name: (SeatID) -> String?) {
        let seats = order.filter { round.hands[$0] != nil } + round.hands.keys.filter { !order.contains($0) }.sorted()
        var knockerID: UUID?
        var entries: [Entry] = []
        for (index, seat) in seats.enumerated() {
            let entry = Entry(name: name(seat) ?? "Player \(index + 1)", hand: round.hands[seat] ?? 0)
            if seat == round.knocker { knockerID = entry.id }
            entries.append(entry)
        }
        self.init(entries: entries, knocker: knockerID)
    }

    // MARK: Results

    private var hands: [UUID: Int] { Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.hand) }) }

    var isValid: Bool {
        Self.playerRange.contains(entries.count) && entries.contains { $0.id == knocker }
            && entries.allSatisfy { Round.handRange.contains($0.hand) }
    }

    var outcome: KnockOutcome? { isValid ? Scoring.knockOutcome(hands: hands, knocker: knocker) : nil }

    var scores: [UUID: Int] { isValid ? Scoring.roundScores(hands: hands, knocker: knocker) : [:] }

    var knockerEntry: Entry? { entries.first { $0.id == knocker } }

    /// The other players with the lowest hand (who beat or tied the knocker).
    var lowestOthers: [Entry] {
        let others = entries.filter { $0.id != knocker }
        guard let low = others.map(\.hand).min() else { return [] }
        return others.filter { $0.hand == low }
    }

    /// "Landed: −10." and friends (literal).
    var verdict: String? {
        guard let outcome, let hand = knockerEntry?.hand else { return nil }
        return Literal.verdict(outcome, hand: hand)
    }

    /// Why, in plain words (literal; the rules are identical in every level).
    var explanation: String? {
        guard let outcome, let knocker = knockerEntry else { return nil }
        let hand = ScoreFormat.string(knocker.hand)
        let names = lowestOthers.map(\.name).formatted(.list(type: .and))
        switch outcome {
        case .landed:
            return "\(knocker.name)'s \(hand) is the lowest hand at the table, so the knock landed: \(ScoreFormat.string(Scoring.landedScore)) flat, whatever the hand."
        case .tied:
            return "\(knocker.name) tied \(names) for the lowest hand, so \(knocker.name) just scores the hand: \(hand)."
        case .failed:
            let low = ScoreFormat.string(lowestOthers.first?.hand ?? 0)
            return "\(names) had \(low), lower than \(knocker.name)'s \(hand), so the knock failed: \(hand) + \(Scoring.failedPenalty) = \(ScoreFormat.string(knocker.hand + Scoring.failedPenalty))."
        case .noPenalty:
            let low = ScoreFormat.string(lowestOthers.first?.hand ?? 0)
            return "\(names) had \(low), lower than \(knocker.name)'s \(hand), but \(knocker.name) went out with all four cards, so there's no penalty: \(hand)."
        }
    }

    // MARK: Editing

    mutating func addPlayer() {
        guard entries.count < Self.playerRange.upperBound else { return }
        entries.append(Entry(name: "Player \(entries.count + 1)", hand: 0))
    }

    mutating func remove(_ id: UUID) {
        guard entries.count > Self.playerRange.lowerBound else { return }
        entries.removeAll { $0.id == id }
        if !entries.contains(where: { $0.id == knocker }), let first = entries.first { knocker = first.id }
    }
}
