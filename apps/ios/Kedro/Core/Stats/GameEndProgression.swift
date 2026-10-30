import Foundation

/// What a finished game did to everyone's progression: the game-end summary's Ratings, Badges
/// earned and Hall of Shame cards (design §10 items 4–5, §12.5). For the Table agent.
///
/// ```swift
/// let progression = await GameEndProgression.load(for: session.gameID, store: app.store, viewer: app.profile?.identity)
/// for change in progression?.ratingChanges ?? [] where change.isRated { … }   // "+18"
/// progression?.debuts                                                         // Ben: W-05 with rating 986
/// ```
nonisolated struct GameEndProgression: Hashable, Sendable {
    struct Debut: Hashable, Sendable {
        var player: PlayerRef
        var name: String
        var rating: Int
    }

    struct Earned: Hashable, Sendable {
        var player: PlayerRef
        var name: String
        var badges: [BadgeAward]
    }

    struct RankMovement: Hashable, Sendable {
        var scope: LeaderboardScope
        var before: Rank?
        var after: Rank?

        /// Places gained (positive) or lost.
        var places: Int? {
            guard let before, let after else { return nil }
            return before.position - after.position
        }
    }

    var gameID: GameID
    /// In seat order. Show a rating only when `isRated` (hidden until game 5).
    var ratingChanges: [RatingChange]
    /// Anyone who just finished game 5, revealed to the whole table (W-05).
    var debuts: [Debut]
    /// Badges earned this game, in seat order.
    var badgesEarned: [Earned]
    /// New top-3 Hall of Shame entries set by this game (HS-08), among the viewer's people.
    var shameInductions: [ShameEntry]
    /// Each seat's title to display after this game (held titles recalculated), as `TI-xx`.
    var titles: [PlayerRef: TitleID]
    /// The viewer's board movement (Played With, by rating).
    var viewerRank: RankMovement?
    /// The viewer's next goal: the closest badge (W-12 style).
    var viewerNextUp: BadgeProgress?

    func ratingChange(for player: PlayerRef) -> RatingChange? { ratingChanges.first { $0.player == player } }
}

extension StatsSnapshot {
    /// The progression for a finished game in this snapshot.
    ///
    /// - Parameters:
    ///   - chosenTitles: Titles people picked (seat snapshots or profiles), validated here.
    func gameEnd(for gameID: GameID, viewer: PlayerRef?, chosenTitles: [PlayerRef: String] = [:], now: Date = .now) -> GameEndProgression? {
        guard let game = game(gameID) else { return nil }
        let changes = ratingChanges(for: gameID)
        let ordered = game.refs.compactMap { changes[$0] }
        let debuts = ordered.filter(\.isDebut).map {
            GameEndProgression.Debut(player: $0.player, name: name(of: $0.player), rating: $0.displayAfter)
        }
        let earned = game.refs.compactMap { ref -> GameEndProgression.Earned? in
            guard let awards = badgesEarned[gameID]?[ref], !awards.isEmpty else { return nil }
            let sorted = awards.sorted { ($0.badge.definition.tier, $0.badge.rawValue) > ($1.badge.definition.tier, $1.badge.rawValue) }
            return .init(player: ref, name: game.participant(ref)?.name ?? name(of: ref), badges: sorted)
        }
        // Inductions are judged against history up to and including this game.
        let through = StatsSnapshot(games: Array(games.prefix(game.index + 1)), options: options, calendar: calendar)
        let inductions = through.shameInductions(for: gameID, viewer: viewer)

        var titles: [PlayerRef: TitleID] = [:]
        for participant in game.participants {
            let chosen = chosenTitles[participant.ref] ?? participant.titleID
            if let title = through.displayTitle(for: participant.ref, chosen: chosen, now: now) {
                titles[participant.ref] = title
            }
        }

        var movement: GameEndProgression.RankMovement?
        var nextUp: BadgeProgress?
        if let viewer = viewer.map(options.canonical), game.contains(viewer) {
            let earlier = before(gameID)
            movement = .init(
                scope: .playedWith,
                before: earlier.ratingRank(of: viewer, scope: .playedWith, viewer: viewer),
                after: through.ratingRank(of: viewer, scope: .playedWith, viewer: viewer)
            )
            nextUp = through.record(viewer).flatMap { BadgeEvaluator.progress($0).first }
        }
        return GameEndProgression(
            gameID: gameID, ratingChanges: ordered, debuts: debuts, badgesEarned: earned,
            shameInductions: inductions, titles: titles, viewerRank: movement, viewerNextUp: nextUp
        )
    }
}

extension GameEndProgression {
    /// Loads the store's finished games and builds the progression for one of them. nil until the
    /// game is finished (abandoned games never count).
    static func load(for gameID: GameID, store: any GameStore, viewer: PlayerRef?, options: StatsOptions = StatsOptions()) async -> GameEndProgression? {
        guard let states = try? await store.finishedGames() else { return nil }
        let snapshot = await StatsSnapshot.buildInBackground(states, options: options)
        return snapshot.gameEnd(for: gameID, viewer: viewer)
    }
}
