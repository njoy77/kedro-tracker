import Foundation

/// One sound to play, `delay` after the change that caused it.
nonisolated struct SoundCue: Hashable, Sendable {
    var moment: SoundMoment
    var delay: Duration = .zero
}

/// Who this phone is at the table, for deciding which sounds it plays.
nonisolated struct SoundListener: Sendable {
    var device: DeviceID
    var seat: SeatID?
    /// This phone plays the shared moments (`TableSpeaker.isThisPhone`).
    var isTableSpeaker: Bool
    /// Seats getting learner treatment: their own bad outcomes never get a sound (design §4.3).
    var learners: Set<SeatID>
    /// The phone that sent each operation (for "Round saved": saving phone only).
    var deviceForOperation: [UUID: DeviceID]
    /// Taunts this phone hides (muted, blocked, reported, custom off) never make a sound.
    var hiddenTaunts: Set<UUID> = []
}

/// Turns a change in the game state into the sounds this phone plays (design §3.8). Pure, so
/// every rule is unit-tested.
///
/// | Moment | Plays on |
/// |---|---|
/// | Live knock marked, knock landed/tied/failed, red King, dead last, debut | Table speaker |
/// | Round saved | The saving phone |
/// | Taunt received | The recipient's phone (the table speaker for "the table") |
/// | Winner | Every phone at game end |
///
/// A knock that fails for a learner, and last place for a learner, stay silent.
nonisolated enum SoundCues {
    /// Gap between the card snap and the outcome on a phone that plays both.
    static let outcomeDelay: Duration = .milliseconds(350)
    /// After the neigh (3 s).
    static let afterWinner: Duration = .milliseconds(3_100)
    static let afterDeadLast: Duration = .milliseconds(1_600)

    static func cues(from old: GameState, to new: GameState, listener: SoundListener) -> [SoundCue] {
        var cues: [SoundCue] = []

        // Live knock marked (a new mark, not a clear).
        if listener.isTableSpeaker, let knock = new.liveKnock, knock.opId != old.liveKnock?.opId {
            cues.append(SoundCue(moment: .liveKnock))
        }

        // A round saved.
        if new.rounds.count > old.rounds.count, let record = new.lastRound {
            var outcomeDelay: Duration = .zero
            if listener.deviceForOperation[record.opId] == listener.device {
                cues.append(SoundCue(moment: .roundSaved))
                outcomeDelay = Self.outcomeDelay
            }
            if listener.isTableSpeaker, let moment = outcomeMoment(for: record, learners: listener.learners) {
                cues.append(SoundCue(moment: moment, delay: outcomeDelay))
            }
        }

        // Taunts received.
        let oldTaunts = Set(old.taunts.map(\.tauntId))
        let received = new.taunts.contains { taunt in
            guard !oldTaunts.contains(taunt.tauntId), !taunt.isRetracted, !listener.hiddenTaunts.contains(taunt.tauntId),
                  listener.deviceForOperation[taunt.opId] != listener.device
            else { return false }
            if let seat = listener.seat, taunt.from == seat { return false }
            switch taunt.target {
            case .seat(let target): return target == listener.seat
            case .table: return listener.isTableSpeaker
            }
        }
        if received { cues.append(SoundCue(moment: .tauntReceived)) }

        // Game end.
        if old.status != .finished, new.status == .finished {
            cues.append(SoundCue(moment: .winner))
            if listener.isTableSpeaker {
                var delay = afterWinner
                let last = deadLastSeats(in: new)
                if !last.isEmpty, last.isDisjoint(with: listener.learners) {
                    cues.append(SoundCue(moment: .deadLast, delay: delay))
                    delay += afterDeadLast
                }
                if !debuts(in: new).isEmpty {
                    cues.append(SoundCue(moment: .debut, delay: delay))
                }
            }
        }
        return cues
    }

    /// The table-speaker sound for a saved round, or nil to stay quiet.
    static func outcomeMoment(for record: RoundRecord, learners: Set<SeatID>) -> SoundMoment? {
        guard let outcome = record.outcome else { return nil }
        // Never for a learner's own failed knock.
        if outcome == .failed, let knocker = record.knocker, learners.contains(knocker) { return nil }
        if record.redKingDecided { return .redKing }
        switch outcome {
        case .landed: return .knockLanded
        case .tied, .noPenalty: return .knockTied
        case .failed: return .knockFailed
        }
    }

    /// Everyone sharing last place in a finished game (nobody when everyone tied).
    static func deadLastSeats(in state: GameState) -> Set<SeatID> {
        guard state.standings.count > 1, let worst = state.standings.map(\.total).max(),
              let best = state.standings.map(\.total).min(), worst != best
        else { return [] }
        return Set(state.standings.filter { $0.total == worst }.map(\.id))
    }

    /// Signed-up players whose ranking game this was: their debut on the board (design §10).
    static func debuts(in state: GameState) -> [SeatID] {
        state.seats.filter { !$0.isGuest && $0.gamesPlayed == Ratings.rankedAfterGames - 1 }.map(\.id)
    }
}
