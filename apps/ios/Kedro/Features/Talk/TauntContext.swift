import Foundation

/// The moments that make taunts relevant right now, for one sender and target (design §8.1:
/// "filtered to what's relevant right now, e.g. after a failed knock, the Knocks group shows first").
nonisolated struct TauntContext: Hashable, Sendable {
    var moments: Set<TauntMoment>

    init(moments: Set<TauntMoment>) {
        self.moments = moments
    }

    init(state: GameState, target: TauntTarget, sender: SeatID?) {
        var moments: Set<TauntMoment> = []
        let targetSeat: SeatID? = if case .seat(let seat) = target { seat } else { nil }
        /// The moment is about `seat`: true when aiming at them or at the whole table.
        func concerns(_ seat: SeatID?) -> Bool { targetSeat == nil || (seat != nil && targetSeat == seat) }

        if let knock = state.liveKnock, knock.roundNumber == state.nextRoundNumber, concerns(knock.knocker) {
            moments.insert(.liveKnock)
        }
        if let last = state.lastRound {
            if concerns(last.knocker) {
                switch last.outcome {
                case .failed: moments.insert(.knockFailed)
                case .landed: moments.insert(.knockLanded)
                case .tied: moments.insert(.knockTied)
                case nil: break
                }
            }
            if last.redKingDecided {
                let redKingHolders = last.round.hands.filter { $0.value < 0 }.map(\.key)
                if targetSeat == nil || redKingHolders.contains(where: { $0 == targetSeat }) {
                    moments.insert(.redKing)
                }
            }
        }
        if !state.rounds.isEmpty, let targetSeat, let total = state.totals[targetSeat] {
            let totals = state.standings.map(\.total)
            let best = totals.min() ?? total
            let worst = totals.max() ?? total
            if total == best { moments.insert(.leader) }
            if total == worst, worst != best { moments.insert(.lastPlace) }
        }
        if !state.rounds.isEmpty, let sender, let mine = state.totals[sender] {
            let rival = targetSeat.flatMap { state.totals[$0] } ?? state.standings.map(\.total).min() ?? mine
            if mine > rival { moments.insert(.comeback) }
        }
        if state.status == .active, state.progress.remainingRounds == 1 {
            moments.insert(.lastRound)
        }
        self.moments = moments
    }
}

extension TauntTarget {
    /// The Talk sheet's default target (design §8.1): the player who just did something
    /// roastable (a live knock, then the last round's knocker), otherwise the table. Never `me`.
    static func suggested(for state: GameState, me: SeatID?) -> TauntTarget {
        if let knock = state.liveKnock, knock.roundNumber == state.nextRoundNumber, knock.knocker != me {
            return .seat(knock.knocker)
        }
        if let last = state.lastRound, last.knocker != me, last.outcome != nil {
            return .seat(last.knocker)
        }
        return .table
    }
}
