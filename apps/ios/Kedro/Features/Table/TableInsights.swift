import SwiftUI

/// What the Table and game end need from Stats (titles, ratings, badges, Hall of Shame), as an
/// adapter so this feature never depends on `Core/Stats` directly. Stats computes them; the app
/// installs a real one with `.environment(\.tableInsights, …)` on the Table's cover.
///
/// The default shows the title snapshot on each seat and nothing at game end, which is the
/// spec's "show nothing if unavailable".
nonisolated struct TableInsights: Sendable {
    /// The title copy ID (`TI-xx`) under a seat's name, or nil to show no title.
    var titleID: @Sendable (Seat) -> String?
    /// Game-end extras for a finished game.
    var gameEnd: @Sendable (GameState) async -> GameEndInsights

    init(
        titleID: @escaping @Sendable (Seat) -> String? = { $0.titleID },
        gameEnd: @escaping @Sendable (GameState) async -> GameEndInsights = { _ in .empty }
    ) {
        self.titleID = titleID
        self.gameEnd = gameEnd
    }

    /// Titles from the seat snapshot, no game-end extras.
    static let seatSnapshot = TableInsights()
}

/// Ratings, badges and Hall of Shame inductions for a finished game (design §10 items 4 and 5).
nonisolated struct GameEndInsights: Hashable, Sendable {
    var ratings: [SeatID: RatingChange] = [:]
    var badges: [EarnedBadge] = []
    var hallOfShame: [ShameInduction] = []

    static let empty = GameEndInsights()

    var isEmpty: Bool { ratings.isEmpty && badges.isEmpty && hallOfShame.isEmpty }
}

nonisolated struct RatingChange: Hashable, Sendable {
    /// nil before the player's 5th game (not yet ranked).
    var before: Int?
    var after: Int
    /// The game that put them on the board (W-05): "Ben's on the board. 986."
    var isDebut: Bool

    var delta: Int? { before.map { after - $0 } }
}

nonisolated struct EarnedBadge: Hashable, Sendable, Identifiable {
    var seat: SeatID
    /// The badge's name ("Comeback Kid"), literal.
    var name: String
    /// The badge line's copy ID (`BG-xx`), rendered in the viewer's level.
    var lineID: String?

    var id: String { seat.rawValue + "|" + name }
}

nonisolated struct ShameInduction: Hashable, Sendable, Identifiable {
    var seat: SeatID
    /// The category's literal name ("Worst Knock").
    var category: String

    var id: String { seat.rawValue + "|" + category }
}

extension EnvironmentValues {
    @Entry var tableInsights: TableInsights = .seatSnapshot
}
