import Foundation

/// "What changes" before Save Change (design §9.2): every affected round score and total, before →
/// after, plus whether the knock outcome or the knocker changes (which needs a confirmation).
/// Pure: built from the current state and `GameSession.preview(_:)`.
nonisolated struct CorrectionPreview: Hashable, Sendable {
    struct Line: Hashable, Sendable, Identifiable {
        var seat: SeatID
        /// The round score, if it changed.
        var round: Change<Int>?
        /// The cumulative total, if it changed.
        var total: Change<Int>?

        var id: SeatID { seat }
    }

    let roundNumber: Int
    /// One line per affected seat, in seat order.
    let lines: [Line]
    let knocker: Change<SeatID>?
    /// Set when the knock's outcome flips (landed, tied, failed).
    let outcome: Change<KnockOutcome>?
    /// The knocker's round score before → after (for the confirmation).
    let knockerScore: Change<Int>?
    /// The knocker after the edit.
    let knockerSeat: SeatID?

    init(before: GameState, after: GameState, roundNumber: Int) {
        self.roundNumber = roundNumber
        let old = before.round(roundNumber)
        let new = after.round(roundNumber)
        let oldTotals = before.totals
        let newTotals = after.totals
        lines = before.seats.compactMap { seat in
            let id = seat.id
            var line = Line(seat: id)
            if let o = old?.scores[id], let n = new?.scores[id], o != n { line.round = Change(before: o, after: n) }
            if let o = oldTotals[id], let n = newTotals[id], o != n { line.total = Change(before: o, after: n) }
            return line.round == nil && line.total == nil ? nil : line
        }
        if let old, let new, old.knocker != new.knocker {
            knocker = Change(before: old.knocker, after: new.knocker)
        } else {
            knocker = nil
        }
        if let o = old?.outcome, let n = new?.outcome, o != n {
            outcome = Change(before: o, after: n)
        } else {
            outcome = nil
        }
        knockerSeat = new?.knocker
        if let new, let o = old?.scores[new.knocker], let n = new.scores[new.knocker] {
            knockerScore = Change(before: o, after: n)
        } else {
            knockerScore = nil
        }
    }

    var isEmpty: Bool { lines.isEmpty && knocker == nil }

    /// Changing the knocker, or any edit that flips a knock outcome, asks first (design §9.2).
    var needsConfirmation: Bool { knocker != nil || outcome != nil }

    /// "Cleo's knock: failed → landed, 12 → −10. Everyone sees this." or the knocker change.
    func confirmationText(name: (SeatID) -> String) -> String? {
        if let knocker {
            return TableText.text("label.knockerChangeConfirm", ["r": roundNumber, "before": name(knocker.before), "after": name(knocker.after)])
        }
        if let outcome, let knockerScore, let knockerSeat {
            return TableText.text("label.knockFlipConfirm", [
                "knocker": name(knockerSeat),
                "before": outcome.before.word, "after": outcome.after.word,
                "old": knockerScore.before, "new": knockerScore.after,
            ])
        }
        return nil
    }

    /// One literal line per affected seat: "Sam: R4 1 → −1 · total 44 → 42".
    func text(for line: Line, name: (SeatID) -> String) -> String {
        if let round = line.round, let total = line.total {
            return TableText.text("label.whatChangesLine", [
                "name": name(line.seat), "r": roundNumber, "old": round.before, "new": round.after,
                "oldTotal": total.before, "newTotal": total.after,
            ])
        }
        if let round = line.round {
            return TableText.text("label.whatChangesRound", ["name": name(line.seat), "r": roundNumber, "old": round.before, "new": round.after])
        }
        if let total = line.total {
            return TableText.text("label.whatChangesTotalOnly", ["name": name(line.seat), "oldTotal": total.before, "newTotal": total.after])
        }
        return ""
    }
}
