import Foundation

/// The shared reveal on the Table (design §7.4). In self-report mode the round that just completed
/// stays face down until its reveal time, identical on every phone (`SelfReportReveal`): the Table
/// shows the game as it was before that round, then flips to the real state.
nonisolated enum TableReveal {
    /// What the Table should show at `now`: the real state, or the state before the completing
    /// operation while the reveal is pending. `isHidden` is true while pending.
    static func visibleState(state: GameState, operations: [GameOperation], now: Date) -> (state: GameState, isHidden: Bool) {
        guard let last = state.lastRound,
              SelfReportReveal.isHidden(last, mode: state.config.scoringMode, now: now),
              let completing = operations.last(where: { $0.opId == last.opId })
        else { return (state, false) }
        let before = operations.filter { GameOperation.foldOrder($0, completing) }
        return (GameState.fold(before, gameID: state.gameID), true)
    }

    /// When the pending reveal flips, if one is pending.
    static func pendingRevealTime(state: GameState, now: Date) -> Date? {
        guard let last = state.lastRound, SelfReportReveal.isHidden(last, mode: state.config.scoringMode, now: now) else { return nil }
        return SelfReportReveal.revealTime(for: last)
    }
}
