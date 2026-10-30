import Foundation

/// Who did something, resolved from an operation's actor.
nonisolated struct GameActor: Hashable, Sendable {
    /// The actor's seat, if they're seated at this table.
    var seat: SeatID?
    /// Display name ("Ben"), "Someone" if unknown, or "Kedro" for system actions.
    var name: String

    static let system = GameActor(seat: nil, name: "Kedro")
}

/// One entry in "On the record" (PRD §4.5, design §9.1): who, when, before → after, and the
/// downstream effect on totals. Text is literal (identical in every language level).
nonisolated struct AuditEntry: Hashable, Sendable, Identifiable {
    /// The operation that made the change.
    var opId: UUID
    var hlc: HLC
    var actor: GameActor
    var change: AuditChange
    /// Totals before → after for every seat whose total moved.
    var effects: [ScoreEffect]
    /// The literal line, without the time ("Ben changed Sam's R4 hand 1 → −1"). Append
    /// " at {time}" in the UI (audit template, copy deck §20).
    var summary: String

    var id: UUID { opId }
    var at: Date { hlc.date }
}

/// Before → after for one value.
nonisolated struct Change<Value: Hashable & Sendable>: Hashable, Sendable {
    var before: Value
    var after: Value
}

nonisolated struct HandChange: Hashable, Sendable {
    var seat: SeatID
    var before: Int
    var after: Int
}

/// A seat's cumulative total before and after a change ("Here's who this screws.", H-01).
nonisolated struct ScoreEffect: Hashable, Sendable, Identifiable {
    var seat: SeatID
    var before: Int
    var after: Int

    var id: SeatID { seat }
    var delta: Int { after - before }
}

nonisolated enum AuditChange: Hashable, Sendable {
    /// A round correction. `knocker` and `outcome` are set only when they changed.
    case roundEdited(round: Int, hands: [HandChange], knocker: Change<SeatID>?, outcome: Change<KnockOutcome?>?)
    /// The latest round was undone.
    case roundUndone(round: Int)
    /// The Round sheet saved a different knocker than the live knock marked (design §7.5).
    case knockerOverridden(round: Int, marked: SeatID, recorded: SeatID)
    /// Extend (or shorten) the planned rounds.
    case plannedRoundsChanged(Change<Int>)
    case dealerChanged(round: Int, before: SeatID?, after: SeatID)
    case scorekeeperChanged(before: SeatID?, after: SeatID)
    case seatRemoved(seat: SeatID, name: String)
    /// Someone sat down after Round 1, starting at the highest total.
    case lateJoin(seat: SeatID, round: Int, startingScore: Int)
    /// A phone took over a seat after the game started ("Is this Sam? · Yes, that's me").
    case seatLinked(seat: SeatID)
    case finished(FinishReason, afterRound: Int)
    case abandoned
    case restored
    /// A second version of a round came in and was set aside (H-06).
    case duplicateRound(round: Int)
    /// An operation arrived too late to apply (H-05).
    case lateOperation(OperationType, LateOperation.Reason)
}

/// One item in the game feed (design §8.4).
nonisolated struct FeedEntry: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case roundSaved(round: Int)
        case liveKnock(LiveKnock)
        case taunt(TauntRecord)
        case reaction(round: Int, seat: SeatID, reaction: Reaction)
        case receipt(ReceiptRecord)
        /// Any "On the record" entry (edits, extend, dealer changes, finish, abandon…).
        case record(AuditEntry)
    }

    var opId: UUID
    var hlc: HLC
    var kind: Kind

    var id: UUID { opId }
    var at: Date { hlc.date }
}

// MARK: - Literal text

nonisolated enum AuditText {
    /// The literal "On the record" line for a change (copy deck §20, D-06).
    static func summary(for change: AuditChange, actor: String, name: (SeatID) -> String) -> String {
        switch change {
        case let .roundEdited(round, hands, knocker, _):
            var parts: [String] = hands.map {
                "\(actor) changed \(name($0.seat))'s R\(round) hand \(ScoreFormat.string($0.before)) → \(ScoreFormat.string($0.after))"
            }
            if let knocker {
                parts.append("\(actor) changed the R\(round) knocker \(name(knocker.before)) → \(name(knocker.after))")
            }
            return parts.isEmpty ? "\(actor) re-saved R\(round) with no changes" : parts.joined(separator: "; ")
        case .roundUndone(let round):
            return "\(actor) undid Round \(round)"
        case let .knockerOverridden(round, marked, recorded):
            return "\(actor) saved R\(round) with \(name(recorded)) knocking (marked live: \(name(marked)))"
        case .plannedRoundsChanged(let change):
            return change.after > change.before
                ? "\(actor) added \(change.after - change.before) rounds. Now playing to \(change.after)"
                : "\(actor) changed the game to \(change.after) rounds"
        case let .dealerChanged(_, _, after):
            return "\(actor) set the dealer to \(name(after))"
        case let .scorekeeperChanged(_, after):
            return "\(actor) handed scorekeeping to \(name(after))"
        case let .seatRemoved(_, removedName):
            return "\(actor) removed \(removedName)"
        case let .lateJoin(seat, round, startingScore):
            return "\(name(seat)) joined for Round \(round), starting at \(ScoreFormat.string(startingScore))"
        case .seatLinked(let seat):
            return "\(name(seat))'s phone took the seat"
        case let .finished(reason, afterRound):
            switch reason {
            case .completed: return "\(actor) finished the game after Round \(afterRound)"
            case .endedEarly: return "\(actor) ended the game early after Round \(afterRound)"
            case .autoFinished: return "Locked automatically after 15 minutes without changes"
            }
        case .abandoned:
            return "\(actor) abandoned the game"
        case .restored:
            return "\(actor) restored the game"
        case .duplicateRound(let round):
            return "Two versions of Round \(round) came in. Kept the first"
        case let .lateOperation(type, reason):
            switch reason {
            case .afterFinish: return "\(actor)'s \(type.rawValue) arrived after the game was locked, so it wasn't applied"
            case .afterAbandon: return "\(actor)'s \(type.rawValue) arrived after the game was abandoned, so it wasn't applied"
            default: return "\(actor)'s \(type.rawValue) couldn't be applied"
            }
        }
    }
}
