import Foundation

/// Turns a folded game into Live Activity content (design §13.2). Pure: the controller calls it
/// on every change, the tests pin it against the sample game, and the backend's broadcast
/// pushes must produce the same shape.
///
/// Language follows the viewer's own level (owner decision), so `voice` is `AppModel.voice`,
/// never the house voice. Literal strings (buttons, the metadata line, the fact line) are
/// identical in every level.
nonisolated enum LiveActivityContent {
    /// What this phone is in the game.
    struct Viewer: Hashable, Sendable {
        /// This phone's seat; nil for a watcher.
        var seat: SeatID?
        /// Scorekeeper mode: this phone keeps score.
        var isScorekeeper: Bool

        init(seat: SeatID?, isScorekeeper: Bool) {
            self.seat = seat
            self.isScorekeeper = isScorekeeper
        }

        @MainActor
        init(_ session: GameSession) {
            self.init(seat: session.mySeatID, isScorekeeper: session.isScorekeeper)
        }
    }

    static func attributes(for state: GameState, viewer: Viewer) -> LiveGameAttributes {
        LiveGameAttributes(
            gameID: state.gameID.uuidString.lowercased(),
            tableWord: state.config.tableWord,
            mySeatID: viewer.seat?.rawValue
        )
    }

    /// The Live Activity phase for a game; nil in the lobby (no activity before Deal).
    static func phase(for status: GameStatus) -> LiveGamePhase? {
        switch status {
        case .lobby: nil
        case .active: .active
        case .finished: .finished
        case .abandoned: .abandoned
        }
    }

    /// The content for a game that has been dealt. nil in the lobby.
    static func contentState(
        for state: GameState,
        viewer: Viewer,
        voice: Voice,
        now: Date = .now
    ) -> LiveGameAttributes.ContentState? {
        guard let phase = phase(for: state.status) else { return nil }
        let round = state.progress.currentRound
        let planned = state.config.plannedRounds

        return LiveGameAttributes.ContentState(
            phase: phase,
            roundNumber: round,
            plannedRounds: planned,
            metadataLine: metadataLine(for: state),
            rows: rows(for: state, viewer: viewer),
            factLine: factLine(for: state),
            liveKnockLine: liveKnockLine(for: state, voice: voice),
            staleTemplate: voice.line("N-06"),
            action: action(for: state, viewer: viewer),
            updatedAt: Int(now.timeIntervalSince1970)
        )
    }

    // MARK: Lines

    /// "ROUND 6 OF 8 · NOAH DEALS" while a dealer is known, else "ROUND 6 OF 8".
    static func metadataLine(for state: GameState) -> String {
        let roundOf = Literal.roundOf(state.progress.currentRound, state.config.plannedRounds)
        guard state.status == .active, !state.isAwaitingFinish, let dealer = state.currentDealer else { return roundOf }
        // `label.deals` is "{word} · {name} DEALS"; the round label takes the word's place.
        return Literal.deals(word: roundOf, dealer: state.name(of: dealer))
    }

    /// "Round 5. Noah knocked on 2." for the latest round.
    static func factLine(for state: GameState) -> String? {
        guard let last = state.lastRound else { return nil }
        let hand = last.round.hands[last.knocker] ?? 0
        return Literal.fact(round: last.number, knocker: state.name(of: last.knocker), hand: hand)
    }

    /// "Sam knocked · last turns" (K-23) while a live knock is marked for the round being played.
    static func liveKnockLine(for state: GameState, voice: Voice) -> String? {
        guard state.status == .active, let knock = state.liveKnock, knock.roundNumber == state.nextRoundNumber else { return nil }
        return voice.line("K-23", ["knocker": state.name(of: knock.knocker)])
    }

    /// Record Round (the scorekeeper) or Report Your Hand (self-report, while this phone still
    /// owes a hand). nil for everyone else, once every round is in, and after the game.
    static func action(for state: GameState, viewer: Viewer) -> LiveActivityButton? {
        guard state.status == .active, !state.isAwaitingFinish, let me = viewer.seat else { return nil }
        switch state.config.scoringMode {
        case .scorekeeper:
            guard viewer.isScorekeeper else { return nil }
            return LiveActivityButton(kind: .recordRound, title: Literal.recordRound(state.nextRoundNumber))
        case .selfReport:
            guard owesReport(state, me: me) else { return nil }
            return LiveActivityButton(kind: .reportHand, title: Literal.text("button.reportHand"))
        }
    }

    /// Self-report: this phone still has to report its own hand, or one it reports for.
    static func owesReport(_ state: GameState, me: SeatID) -> Bool {
        guard state.status == .active, state.config.scoringMode == .selfReport, !state.isAwaitingFinish else { return false }
        let waiting = state.selfReport.map(\.waitingOn) ?? state.seats.map(\.id)
        return waiting.contains { seat in seat == me || state.seat(seat)?.reporter == me }
    }

    // MARK: Rows

    static func rows(for state: GameState, viewer: Viewer) -> [LiveStandingRow] {
        let hasRounds = !state.rounds.isEmpty
        return state.standings.map { standing in
            LiveStandingRow(
                id: standing.id.rawValue,
                name: standing.seat.displayName,
                rankLabel: standing.rank.label,
                ordinal: standing.rank.ordinal,
                score: ScoreFormat.string(standing.total),
                delta: standing.lastRound.map(delta),
                outcome: standing.lastRound?.outcome.map(outcome),
                isMe: standing.id == viewer.seat,
                isLeader: hasRounds && standing.isLeader,
                isDealer: state.status == .active && standing.isDealer,
                avatar: avatar(for: standing.seat)
            )
        }
    }

    /// The shortest honest delta: "+9" for most seats, the knock math for the knocker
    /// ("−10" landed, "5" tied, "2 + 10" failed), next to the outcome glyph.
    static func delta(_ result: SeatRoundResult) -> String {
        switch result.outcome {
        case .landed: ScoreFormat.string(Scoring.landedScore)
        case .tied: ScoreFormat.string(result.hand)
        case .failed: "\(ScoreFormat.string(result.hand)) + \(Scoring.failedPenalty)"
        case nil: ScoreFormat.signed(result.score)
        }
    }

    static func outcome(_ outcome: KnockOutcome) -> LiveKnockOutcome {
        switch outcome {
        case .landed: .landed
        case .tied: .tied
        case .failed: .failed
        }
    }

    /// Photos can't load in the extension (no network), so they fall back to the initial.
    static func avatar(for seat: Seat) -> LiveAvatar {
        switch seat.avatar {
        case .emoji(let emoji, let colorIndex): .emoji(emoji: emoji, colorIndex: colorIndex)
        case .curated(let id): .curated(id: id.rawValue)
        case .photo, nil: .initial(letter: seat.initial, isGuest: seat.isGuest)
        }
    }
}
