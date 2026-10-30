import Foundation

/// One person's part in one finished game.
nonisolated struct PlayerGameResult: Hashable, Sendable, Identifiable {
    var gameID: GameID
    var gameIndex: Int
    var date: Date
    var tableWord: String
    var playerCount: Int
    var finalScore: Int
    var rank: Rank
    var isWinner: Bool
    var isSharedWin: Bool
    var roundsPlayed: Int
    var roundScoreSum: Int
    var knocks: Int
    var landed: Int
    var tied: Int
    var failed: Int
    /// Rounds where this player had a lower hand than a beaten knocker (The Snake).
    var knocksBeaten: Int
    var redKings: Int
    var ghostHands: Int
    var biggestHand: Int
    /// Won from outside the lead at the halfway round.
    var isComeback: Bool
    /// Sole leader after the second-to-last round, then didn't win.
    var bottledFinalRound: Bool
    /// The biggest lead held as sole leader at any point (0 if never led alone).
    var biggestLead: Int
    /// The furthest behind the leader at any point.
    var deepestDeficit: Int
    var ratingBefore: Double
    var ratingAfter: Double
    /// Taunts sent this game (all), and the ones that count for Trash Talker (3 a game).
    var tauntsSent: Int
    var tauntsCounted: Int
    /// Games played before this one (0 for a first game).
    var gamesBefore: Int

    var id: GameID { gameID }

    /// The visible rating change: rounded after minus rounded before.
    var ratingDelta: Int { Int(ratingAfter.rounded()) - Int(ratingBefore.rounded()) }
}

/// One knock, for knock records and the Wrapped knock card.
nonisolated struct KnockEvent: Hashable, Sendable {
    var gameID: GameID
    var gameIndex: Int
    var date: Date
    var tableWord: String
    var roundNumber: Int
    var hand: Int
    var lowestOther: Int?
    var outcome: KnockOutcome
}

/// Everything the replay accumulates for one person. Read through `PlayerStats` and the snapshot's
/// query methods; nothing here is stored outside a snapshot.
nonisolated struct PlayerRecord: Hashable, Sendable, Identifiable {
    var ref: PlayerRef
    /// The latest name, avatar, handle and title seen at a table.
    var identity: StatsParticipant
    /// Oldest first.
    var results: [PlayerGameResult] = []
    var knockEvents: [KnockEvent] = []
    /// How often each opponent finished ahead of this player, and the replay index at which the
    /// count last went up (ties for nemesis go to whoever got there first).
    var finishedAheadOfMe: [PlayerRef: Int] = [:]
    var finishedAheadOfMeAt: [PlayerRef: Int] = [:]
    /// How often this player finished ahead of each opponent.
    var iFinishedAhead: [PlayerRef: Int] = [:]
    var iFinishedAheadAt: [PlayerRef: Int] = [:]
    /// Finished games shared with each opponent.
    var sharedGames: [PlayerRef: Int] = [:]
    /// Consecutive shared games finishing ahead of each opponent (Exorcism).
    var aheadStreak: [PlayerRef: Int] = [:]
    var rating: Double = Ratings.startingRating
    var currentWinStreak = 0
    var longestWinStreak = 0
    var currentLandedStreak = 0
    var longestLandedStreak = 0
    var badges: [BadgeID: BadgeAward] = [:]
    /// When a held-title metric last changed (replay index), for "ties go to whoever got there first".
    var metricChangedAt: [HeldMetric: Int] = [:]
    /// People who sat with this player while they were still a guest identity (Bad Influence).
    var guestEraCompanions: Set<PlayerRef> = []

    var id: PlayerRef { ref }

    init(ref: PlayerRef, identity: StatsParticipant) {
        self.ref = ref
        self.identity = identity
    }

    // MARK: Totals

    var gamesPlayed: Int { results.count }
    var wins: Int { results.count { $0.isWinner } }
    var roundsPlayed: Int { results.reduce(0) { $0 + $1.roundsPlayed } }
    var knocks: Int { knockEvents.count }
    var landed: Int { knockEvents.count { $0.outcome == .landed } }
    var tied: Int { knockEvents.count { $0.outcome == .tied } }
    var failed: Int { knockEvents.count { $0.outcome == .failed } }
    var knocksBeaten: Int { results.reduce(0) { $0 + $1.knocksBeaten } }
    var tauntsCounted: Int { results.reduce(0) { $0 + $1.tauntsCounted } }

    var isRanked: Bool { gamesPlayed >= Ratings.rankedAfterGames }
    var isGuest: Bool { ref.isGuest }

    var winRate: Double? { gamesPlayed > 0 ? Double(wins) / Double(gamesPlayed) : nil }
    var averageFinalScore: Double? {
        gamesPlayed > 0 ? Double(results.reduce(0) { $0 + $1.finalScore }) / Double(gamesPlayed) : nil
    }
    var averageRoundScore: Double? {
        roundsPlayed > 0 ? Double(results.reduce(0) { $0 + $1.roundScoreSum }) / Double(roundsPlayed) : nil
    }
    var knockRate: Double? { roundsPlayed > 0 ? Double(knocks) / Double(roundsPlayed) : nil }
    var knockSuccessRate: Double? { knocks > 0 ? Double(landed) / Double(knocks) : nil }

    /// The displayed rating (a whole number).
    var displayRating: Int { Int(rating.rounded()) }

    /// Accounts and claimed guests this player has shared a table with (anti-farming, §12.6).
    var accountOpponents: [PlayerRef] { sharedGames.keys.filter { !$0.isGuest } }

    /// The opponent who has finished ahead most often; ties go to whoever got there first.
    func nemesis(accountsOnly: Bool = false, excluding excluded: Set<PlayerRef> = []) -> (ref: PlayerRef, count: Int)? {
        finishedAheadOfMe
            .filter { $0.value > 0 && !excluded.contains($0.key) && (!accountsOnly || !$0.key.isGuest) }
            .min { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                let left = finishedAheadOfMeAt[lhs.key] ?? .max, right = finishedAheadOfMeAt[rhs.key] ?? .max
                if left != right { return left < right }
                return lhs.key.seatID < rhs.key.seatID
            }
            .map { ($0.key, $0.value) }
    }

    /// The opponent this player has finished ahead of most often.
    func victim(excluding excluded: Set<PlayerRef> = []) -> (ref: PlayerRef, count: Int)? {
        iFinishedAhead
            .filter { $0.value > 0 && !excluded.contains($0.key) }
            .min { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                let left = iFinishedAheadAt[lhs.key] ?? .max, right = iFinishedAheadAt[rhs.key] ?? .max
                if left != right { return left < right }
                return lhs.key.seatID < rhs.key.seatID
            }
            .map { ($0.key, $0.value) }
    }
}

/// Lifetime stats for a profile (PRD §5.1), read from a `PlayerRecord`.
nonisolated struct PlayerStats: Hashable, Sendable {
    /// A single game behind a record (best/worst game).
    struct GameMark: Hashable, Sendable {
        var gameID: GameID
        var score: Int
        var tableWord: String
        var date: Date
    }

    var player: PlayerRef
    var gamesPlayed: Int
    var wins: Int
    var winRate: Double?
    var bestGame: GameMark?
    var worstGame: GameMark?
    var averageScorePerGame: Double?
    var averageScorePerRound: Double?
    var roundsPlayed: Int
    var currentWinStreak: Int
    var longestWinStreak: Int
    var knocks: Int
    var knockRate: Double?
    var knockSuccessRate: Double?
    var landed: Int
    var tied: Int
    var failed: Int
    var nemesis: PlayerRef?
    var nemesisCount: Int
    /// Rating, replayed from game 1. Shown only once `isRanked`.
    var rating: Int
    var isRanked: Bool
    /// The last five finishes, oldest first.
    var form: [Rank]
    /// The last game's visible rating change.
    var lastRatingDelta: Int?
    var lastGameDate: Date?

    init(record: PlayerRecord, excluded: Set<PlayerRef> = []) {
        player = record.ref
        gamesPlayed = record.gamesPlayed
        wins = record.wins
        winRate = record.winRate
        let best = record.results.min { ($0.finalScore, $0.gameIndex) < ($1.finalScore, $1.gameIndex) }
        let worst = record.results.max { ($0.finalScore, -$0.gameIndex) < ($1.finalScore, -$1.gameIndex) }
        bestGame = best.map { GameMark(gameID: $0.gameID, score: $0.finalScore, tableWord: $0.tableWord, date: $0.date) }
        worstGame = worst.map { GameMark(gameID: $0.gameID, score: $0.finalScore, tableWord: $0.tableWord, date: $0.date) }
        averageScorePerGame = record.averageFinalScore
        averageScorePerRound = record.averageRoundScore
        roundsPlayed = record.roundsPlayed
        currentWinStreak = record.currentWinStreak
        longestWinStreak = record.longestWinStreak
        knocks = record.knocks
        knockRate = record.knockRate
        knockSuccessRate = record.knockSuccessRate
        landed = record.landed
        tied = record.tied
        failed = record.failed
        let nemesis = record.nemesis(excluding: excluded)
        self.nemesis = nemesis?.ref
        nemesisCount = nemesis?.count ?? 0
        rating = record.displayRating
        isRanked = record.isRanked
        form = record.results.suffix(5).map(\.rank)
        lastRatingDelta = record.results.last?.ratingDelta
        lastGameDate = record.results.last?.date
    }
}
