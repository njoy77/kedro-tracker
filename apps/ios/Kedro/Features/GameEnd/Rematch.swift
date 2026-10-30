import Foundation

/// Run It Back (design §5.7, §6.4, §10): the same table plays again. Same seats in the same
/// clockwise order, same rounds and mode, a fresh table word, and the first deal rotates one seat.
nonisolated struct Rematch: Hashable, Sendable {
    var config: GameConfig
    /// Everyone but the host (this phone), clockwise from the seat after the host. The lobby API
    /// puts the host at order 0, so the circle is preserved.
    var others: [Seat]

    /// The plan for a finished game, hosted by `host` (this phone's seat). nil if the host isn't
    /// seated at that table.
    init?(from state: GameState, host: SeatID) {
        let seats = state.seats
        guard let hostIndex = seats.firstIndex(where: { $0.id == host }) else { return nil }
        let count = seats.count
        others = (1..<max(count, 1)).map { offset in
            var seat = seats[(hostIndex + offset) % count]
            seat.order = offset
            // This game now counts toward their record (learner lines, the rank meter).
            seat.gamesPlayed = seat.gamesPlayed.map { $0 + 1 }
            return seat
        }
        let previousFirst = state.config.firstDealerSeat ?? state.hostSeat ?? seats.first?.id
        let firstIndex = previousFirst.flatMap { first in seats.firstIndex { $0.id == first } } ?? 0
        let nextFirst = seats.isEmpty ? nil : seats[(firstIndex + 1) % count].id
        config = GameConfig(
            plannedRounds: state.config.plannedRounds,
            scoringMode: state.config.scoringMode,
            tableWord: TableWord.random(excluding: state.config.tableWord),
            firstDealerSeat: nextFirst,
            houseVoiceCap: state.config.houseVoiceCap,
            scorekeeperSeat: state.config.scorekeeperSeat
        )
    }
}
