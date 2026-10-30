import Foundation

/// The skill rating (design §12.4, PRD §5.3): multiplayer pairwise Elo from the finishing order.
///
/// For a game of n players, every pair (i, j) is one Elo match: i finishing ahead (lower total) is
/// a win, equal totals a draw. Each pair exchanges `K_pair / (n − 1) × (S − E)` points, where
/// `K_pair` is the larger of the two players' K (32, doubled to 64 for a player's first 10 games).
/// Using one K per pair keeps every game zero-sum, so the rating pool never inflates, while a
/// newcomer still moves at double speed. Ratings start at 1,000, are replayed deterministically
/// from every finished, non-abandoned game (so edits, claims and migrated history come out right),
/// are computed from game 1 and are shown from game 5 (the debut).
///
/// The server's replay (`packages/shared`) must use exactly these rules.
nonisolated enum Ratings {
    static let startingRating: Double = 1000
    static let baseK: Double = 32
    /// A player's first `provisionalGames` games use double K.
    static let provisionalGames = 10
    /// Ratings are hidden, and players unranked, until this many games.
    static let rankedAfterGames = 5

    static func k(gamesBefore: Int) -> Double {
        gamesBefore < provisionalGames ? baseK * 2 : baseK
    }

    /// The expected score of a player rated `rating` against `opponent`.
    static func expected(_ rating: Double, against opponent: Double) -> Double {
        1 / (1 + pow(10, (opponent - rating) / 400))
    }

    /// Rating changes for one game.
    ///
    /// - Parameters:
    ///   - totals: Final totals (lower is better).
    ///   - ratings: Ratings before the game (missing players start at 1,000).
    ///   - gamesBefore: Finished games before this one, per player.
    ///   - order: The order pairs are summed in (seat order). Floating-point sums depend on order,
    ///     so pass it whenever the result must match another device or the server exactly.
    /// - Returns: The change for every player in `totals`. The changes sum to zero.
    static func deltas<Key: Hashable>(totals: [Key: Int], ratings: [Key: Double], gamesBefore: [Key: Int], order: [Key]? = nil) -> [Key: Double] {
        var seen: Set<Key> = []
        let players = (order.map { order in order.filter { totals[$0] != nil } } ?? Array(totals.keys)).filter { seen.insert($0).inserted }
        var deltas = Dictionary(uniqueKeysWithValues: players.map { ($0, 0.0) })
        guard players.count >= 2 else { return deltas }
        let scale = 1 / Double(players.count - 1)
        for (offset, i) in players.enumerated() {
            for j in players[(offset + 1)...] {
                let ri = ratings[i] ?? startingRating, rj = ratings[j] ?? startingRating
                let ti = totals[i] ?? 0, tj = totals[j] ?? 0
                let actual: Double = ti < tj ? 1 : (ti == tj ? 0.5 : 0)
                let pairK = max(k(gamesBefore: gamesBefore[i] ?? 0), k(gamesBefore: gamesBefore[j] ?? 0))
                let change = pairK * scale * (actual - expected(ri, against: rj))
                deltas[i, default: 0] += change
                deltas[j, default: 0] -= change
            }
        }
        return deltas
    }
}

/// One person's rating movement in one game (for game end and history rows).
nonisolated struct RatingChange: Hashable, Sendable {
    var player: PlayerRef
    var before: Double
    var after: Double
    /// Finished games before this one.
    var gamesBefore: Int

    var gamesAfter: Int { gamesBefore + 1 }
    var displayBefore: Int { Int(before.rounded()) }
    var displayAfter: Int { Int(after.rounded()) }
    /// The visible change: rounded after minus rounded before.
    var delta: Int { displayAfter - displayBefore }
    /// Ratings show once a player has 5 games.
    var isRated: Bool { gamesAfter >= Ratings.rankedAfterGames }
    /// This game was the player's 5th: their rating is revealed to the whole table (W-05).
    var isDebut: Bool { gamesAfter == Ratings.rankedAfterGames }
}

/// A point on a player's rating line (Wrapped, profile).
nonisolated struct RatingPoint: Hashable, Sendable, Identifiable {
    var gameIndex: Int
    var date: Date
    var rating: Double

    var id: Int { gameIndex }
}
