import Foundation

/// Which people a board ranks (design §12.4).
nonisolated enum LeaderboardScope: String, Hashable, Sendable, CaseIterable, Identifiable {
    /// You among everyone you've shared a table with (the default).
    case playedWith
    /// Everyone. On the phone this is everyone in this phone's history; the server's
    /// `GET /v1/leaderboard?scope=global` is the real global board.
    case global

    var id: String { rawValue }

    /// Literal segment label.
    var label: String {
        switch self {
        case .playedWith: "Played With"
        case .global: "Global"
        }
    }
}

/// What a board is sorted by (design §12.4). The rank shown is the rank for that sort.
nonisolated enum LeaderboardSort: String, Hashable, Sendable, CaseIterable, Identifiable {
    case rating, winRate, wins, avgScore, knockSuccess

    var id: String { rawValue }

    /// Literal menu label.
    var label: String {
        switch self {
        case .rating: "Rating"
        case .winRate: "Win rate"
        case .wins: "Wins"
        case .avgScore: "Avg score"
        case .knockSuccess: "Knock success"
        }
    }

    /// The menu's caption under the label.
    var caption: String? {
        switch self {
        case .winRate: "10+ games"
        case .avgScore: "lower is better"
        case .knockSuccess: "15+ knocks"
        default: nil
        }
    }

    /// "BY WIN RATE" in the header.
    var headerLabel: String { "By " + label.lowercased() }

    /// Lower is better for average score only.
    var ascending: Bool { self == .avgScore }

    /// Per-sort minimum on top of the 5-game eligibility.
    var minimumGames: Int? { self == .winRate ? 10 : nil }
    var minimumKnocks: Int? { self == .knockSuccess ? 15 : nil }

    func meetsMinimum(_ record: PlayerRecord) -> Bool {
        if let games = minimumGames, record.gamesPlayed < games { return false }
        if let knocks = minimumKnocks, record.knocks < knocks { return false }
        return true
    }

    func value(_ record: PlayerRecord) -> Double {
        switch self {
        case .rating: record.rating
        case .winRate: record.winRate ?? 0
        case .wins: Double(record.wins)
        case .avgScore: record.averageFinalScore ?? .infinity
        case .knockSuccess: record.knockSuccessRate ?? 0
        }
    }

    /// The board's number for a value: "1,142", "44%", "11", "31.4", "58%".
    func format(_ value: Double) -> String {
        switch self {
        case .rating: Int(value.rounded()).formatted()
        case .winRate, .knockSuccess: StatsFormat.percent(value)
        case .wins: Int(value).formatted()
        case .avgScore: StatsFormat.decimal(value)
        }
    }

    /// "Close" for L-04: within 15 rating points, 2% win rate, 1 win, 1 point of average, 2% knock success.
    var closeThreshold: Double {
        switch self {
        case .rating: 15
        case .winRate, .knockSuccess: 0.02
        case .wins: 1
        case .avgScore: 1
        }
    }

    /// The gap as said in L-04: "12", "2%", "1 win", "0.4 points".
    func formatGap(_ gap: Double) -> String {
        switch self {
        case .rating: "\(Int(gap.rounded()))"
        case .winRate, .knockSuccess: StatsFormat.percent(gap, precise: true)
        case .wins: Int(gap) == 1 ? "1 win" : "\(Int(gap)) wins"
        case .avgScore: "\(StatsFormat.decimal(gap)) points"
        }
    }
}

/// One ranked (or listed) person on a board.
nonisolated struct LeaderboardRow: Hashable, Sendable, Identifiable {
    var ref: PlayerRef
    var identity: StatsParticipant
    /// nil when listed below a sort's minimum.
    var rank: Rank?
    var value: Double
    var valueText: String
    var gamesPlayed: Int
    var knocks: Int
    var isViewer: Bool
    /// Just ranked (their debut was their latest game): the "new" tag.
    var isNew: Bool
    var lastRatingDelta: Int?

    var id: PlayerRef { ref }
}

/// Someone still in their first ten (Not Yet Ranked, L-02).
nonisolated struct UnrankedRow: Hashable, Sendable, Identifiable {
    var ref: PlayerRef
    var identity: StatsParticipant
    var gamesPlayed: Int
    var isViewer: Bool

    var id: PlayerRef { ref }
    var gamesLeft: Int { max(0, Ratings.rankedAfterGames - gamesPlayed) }
}

/// The person just above the viewer, when they're catchable (L-04).
nonisolated struct CloseRace: Hashable, Sendable {
    var above: PlayerRef
    var name: String
    var gap: Double
    var gapText: String
}

nonisolated struct Leaderboard: Hashable, Sendable {
    var scope: LeaderboardScope
    var sort: LeaderboardSort
    var ranked: [LeaderboardRow]
    /// Eligible (5+ games) but under this sort's minimum: listed after the ranked rows, no number.
    var belowMinimum: [LeaderboardRow]
    var notYetRanked: [UnrankedRow]
    var viewer: PlayerRef?
    var closeRace: CloseRace?

    var viewerRow: LeaderboardRow? { (ranked + belowMinimum).first(where: \.isViewer) }
    var viewerUnranked: UnrankedRow? { notYetRanked.first(where: \.isViewer) }
    var viewerIndex: Int? { ranked.firstIndex(where: \.isViewer) }

    /// The viewer and up to `radius` neighbours either side ("Around me").
    func aroundViewer(radius: Int = 2) -> [LeaderboardRow] {
        guard let index = viewerIndex else { return [] }
        let lower = max(0, index - radius), upper = min(ranked.count, index + radius + 1)
        return Array(ranked[lower..<upper])
    }
}

/// The 2 × 2 records grid (design §12.4), each with a top-25 board.
nonisolated enum RecordKind: String, Hashable, Sendable, CaseIterable, Identifiable {
    case bestGame, longestStreak, mostLandedKnocks, mostGames

    var id: String { rawValue }

    /// Literal label.
    var label: String {
        switch self {
        case .bestGame: "Best game"
        case .longestStreak: "Longest streak"
        case .mostLandedKnocks: "Most landed knocks"
        case .mostGames: "Most games"
        }
    }

    var definition: String {
        switch self {
        case .bestGame: "Lowest final score in a single game."
        case .longestStreak: "Longest run of consecutive wins."
        case .mostLandedKnocks: "Knocks with the strictly lowest hand (−10)."
        case .mostGames: "Finished games, including ended-early ones."
        }
    }
}

nonisolated struct RecordEntry: Hashable, Sendable, Identifiable {
    var rank: Int
    var ref: PlayerRef
    var identity: StatsParticipant
    var value: Int
    var gameID: GameID?
    var tableWord: String?
    var date: Date?

    var id: PlayerRef { ref }
}

extension StatsSnapshot {
    /// The people a board covers: unclaimed guests never appear; blocked people are hidden.
    func boardPopulation(_ scope: LeaderboardScope, viewer: PlayerRef?) -> [PlayerRecord] {
        let candidates: [PlayerRecord]
        switch scope {
        case .global:
            candidates = Array(records.values)
        case .playedWith:
            guard let viewer else { return [] }
            candidates = circle(of: viewer).compactMap { records[$0] }
        }
        return candidates.filter { !$0.isGuest && !options.excluded.contains($0.ref) }
    }

    func leaderboard(scope: LeaderboardScope, sort: LeaderboardSort, viewer: PlayerRef?) -> Leaderboard {
        let viewer = viewer.map(options.canonical)
        let population = boardPopulation(scope, viewer: viewer)
        let eligible = population.filter(\.isRanked)

        func row(_ record: PlayerRecord, rank: Rank?) -> LeaderboardRow {
            let value = sort.value(record)
            return LeaderboardRow(
                ref: record.ref, identity: record.identity, rank: rank, value: value, valueText: sort.format(value),
                gamesPlayed: record.gamesPlayed, knocks: record.knocks, isViewer: record.ref == viewer,
                isNew: record.gamesPlayed == Ratings.rankedAfterGames, lastRatingDelta: record.results.last?.ratingDelta
            )
        }

        let qualifying = eligible.filter(sort.meetsMinimum)
        let ordered = qualifying.sorted { lhs, rhs in
            let left = sort.value(lhs), right = sort.value(rhs)
            if left != right { return sort.ascending ? left < right : left > right }
            if lhs.gamesPlayed != rhs.gamesPlayed { return lhs.gamesPlayed > rhs.gamesPlayed }
            return lhs.identity.name.localizedStandardCompare(rhs.identity.name) == .orderedAscending
        }
        var ranked: [LeaderboardRow] = []
        for record in ordered {
            let value = sort.value(record)
            let better = ordered.count { sort.ascending ? sort.value($0) < value : sort.value($0) > value }
            let equal = ordered.count { sort.value($0) == value }
            ranked.append(row(record, rank: Rank(position: better + 1, isShared: equal > 1)))
        }
        let below = eligible
            .filter { !sort.meetsMinimum($0) }
            .sorted { ($0.gamesPlayed, $0.identity.name) > ($1.gamesPlayed, $1.identity.name) }
            .map { row($0, rank: nil) }
        let unranked = population
            .filter { !$0.isRanked }
            .sorted { lhs, rhs in
                if lhs.gamesPlayed != rhs.gamesPlayed { return lhs.gamesPlayed > rhs.gamesPlayed }
                return lhs.identity.name.localizedStandardCompare(rhs.identity.name) == .orderedAscending
            }
            .map { UnrankedRow(ref: $0.ref, identity: $0.identity, gamesPlayed: $0.gamesPlayed, isViewer: $0.ref == viewer) }

        var board = Leaderboard(scope: scope, sort: sort, ranked: ranked, belowMinimum: below, notYetRanked: unranked, viewer: viewer, closeRace: nil)
        if let index = board.viewerIndex {
            let mine = board.ranked[index]
            // The nearest row with a strictly better value.
            if let above = board.ranked[..<index].last(where: { $0.value != mine.value }) {
                let gap = abs(above.value - mine.value)
                if gap <= sort.closeThreshold + 1e-9 {
                    board.closeRace = CloseRace(above: above.ref, name: above.identity.name, gap: gap, gapText: sort.formatGap(gap))
                }
            }
        }
        return board
    }

    /// A person's rank on a board by rating (for "#13 GLOBAL"), nil when unranked.
    func ratingRank(of ref: PlayerRef, scope: LeaderboardScope = .global, viewer: PlayerRef? = nil) -> Rank? {
        let ref = options.canonical(ref)
        return leaderboard(scope: scope, sort: .rating, viewer: viewer ?? ref).ranked.first { $0.ref == ref }?.rank
    }

    /// A records board (top 25).
    func records(_ kind: RecordKind, scope: LeaderboardScope, viewer: PlayerRef?, limit: Int = 25) -> [RecordEntry] {
        let population = boardPopulation(scope, viewer: viewer.map(options.canonical))
        var entries: [(record: PlayerRecord, value: Int, result: PlayerGameResult?)] = []
        for record in population where record.gamesPlayed > 0 {
            switch kind {
            case .bestGame:
                if let best = record.results.min(by: { ($0.finalScore, $0.gameIndex) < ($1.finalScore, $1.gameIndex) }) {
                    entries.append((record, best.finalScore, best))
                }
            case .longestStreak:
                if record.longestWinStreak > 0 { entries.append((record, record.longestWinStreak, nil)) }
            case .mostLandedKnocks:
                if record.landed > 0 { entries.append((record, record.landed, nil)) }
            case .mostGames:
                entries.append((record, record.gamesPlayed, nil))
            }
        }
        let ascending = kind == .bestGame
        entries.sort { lhs, rhs in
            if lhs.value != rhs.value { return ascending ? lhs.value < rhs.value : lhs.value > rhs.value }
            // Ties: whoever got there first.
            let left = lhs.result?.gameIndex ?? lhs.record.results.last?.gameIndex ?? 0
            let right = rhs.result?.gameIndex ?? rhs.record.results.last?.gameIndex ?? 0
            if left != right { return left < right }
            return lhs.record.ref.seatID < rhs.record.ref.seatID
        }
        var output: [RecordEntry] = []
        for (offset, entry) in entries.prefix(limit).enumerated() {
            let rank = output.last.flatMap { $0.value == entry.value ? $0.rank : nil } ?? offset + 1
            output.append(RecordEntry(
                rank: rank, ref: entry.record.ref, identity: entry.record.identity, value: entry.value,
                gameID: entry.result?.gameID, tableWord: entry.result?.tableWord, date: entry.result?.date
            ))
        }
        return output
    }
}

/// Number formats for stats (true minus via `ScoreFormat` for scores).
nonisolated enum StatsFormat {
    /// "44%"; `precise` keeps one decimal under 10% ("1.5%").
    static func percent(_ fraction: Double, precise: Bool = false) -> String {
        let value = fraction * 100
        if precise, value < 10, value.rounded() != value {
            return String(format: "%.1f%%", value)
        }
        return "\(Int(value.rounded()))%"
    }

    /// "7.1", with a true minus for negatives.
    static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        let text = String(format: "%.1f", abs(value))
        return value < 0 && text != "0.0" ? "\u{2212}" + text : text
    }
}
