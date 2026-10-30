import Foundation

// The Table's `TableInsights` adapter (Features/Table/TableInsights.swift), built from Stats.
// `MainTabView` installs it on the Table's cover with `.environment(\.tableInsights, …)`.

extension TableInsights {
    /// Titles under names from the stats snapshot, and the game-end ratings, badges and Hall of
    /// Shame from `GameEndProgression`.
    ///
    /// - Parameters:
    ///   - titles: The live table's titles (`StatsModel.tableTitles(for:)`), computed once per
    ///     snapshot so rows don't recompute title holders.
    ///   - isLoaded: Whether stats have loaded; until then each seat's own title snapshot shows.
    static func stats(
        titles: [SeatID: TitleID],
        isLoaded: Bool,
        store: any GameStore,
        viewer: PlayerRef?,
        options: StatsOptions
    ) -> TableInsights {
        TableInsights(
            titleID: { seat in
                isLoaded ? titles[seat.id]?.rawValue : seat.titleID
            },
            gameEnd: { state in
                guard state.status == .finished,
                      let progression = await GameEndProgression.load(for: state.gameID, store: store, viewer: viewer, options: options)
                else { return .empty }
                return GameEndInsights(progression, in: state)
            }
        )
    }
}

extension GameEndInsights {
    /// Maps Stats' progression onto the Table's game-end sections. Stats credits a claimed guest
    /// to the account, so each identity is matched back to the seat it sat in.
    nonisolated init(_ progression: GameEndProgression, in state: GameState) {
        func seat(for player: PlayerRef) -> SeatID {
            state.seats.first { $0.player == player }?.id ?? player.seatID
        }
        self.init()
        for change in progression.ratingChanges where change.isRated {
            ratings[seat(for: change.player)] = GameEndRatingChange(
                before: change.gamesBefore >= Ratings.rankedAfterGames ? change.displayBefore : nil,
                after: change.displayAfter,
                isDebut: change.isDebut
            )
        }
        badges = progression.badgesEarned.flatMap { earned in
            earned.badges.map { award in
                EarnedBadge(seat: seat(for: earned.player), name: award.definition.name, lineID: award.badge.rawValue)
            }
        }
        hallOfShame = progression.shameInductions.map { entry in
            ShameInduction(seat: seat(for: entry.player), category: entry.category.name)
        }
    }
}
