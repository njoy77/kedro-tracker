import Foundation

/// The 8 Kedro personas (design §12.9).
nonisolated enum WrappedPersona: String, Hashable, Sendable, CaseIterable {
    case menace, closer, gambler, snake, comeback, accountant, regular, wildcard

    /// The persona's line (WR-15…WR-22). It opens with the persona's name in capitals.
    var copyID: String {
        switch self {
        case .gambler: "WR-15"
        case .snake: "WR-16"
        case .accountant: "WR-17"
        case .menace: "WR-18"
        case .closer: "WR-19"
        case .comeback: "WR-20"
        case .regular: "WR-21"
        case .wildcard: "WR-22"
        }
    }

    /// Literal name ("The Closer").
    var name: String {
        switch self {
        case .gambler: "The Gambler"
        case .snake: "The Snake"
        case .accountant: "The Accountant"
        case .menace: "The Menace"
        case .closer: "The Closer"
        case .comeback: "The Comeback"
        case .regular: "The Regular"
        case .wildcard: "The Wildcard"
        }
    }
}

/// Whether a year's Wrapped can be opened.
nonisolated enum WrappedAvailability: Hashable, Sendable {
    case available
    /// Fewer than 10 finished games that year (WR-23).
    case needsGames(played: Int, needed: Int)
    /// Enough games, but it isn't December 1 yet.
    case arrives(Date)
}

/// One person's year in Kedro (design §12.9). Everything comes from finished, non-abandoned
/// games in the calendar year; other people appear only if they shared games; blocked people never.
nonisolated struct WrappedSummary: Hashable, Sendable {
    static let minimumGames = 10

    struct Person: Hashable, Sendable {
        var ref: PlayerRef
        var name: String
        var count: Int
    }

    var year: Int
    var player: PlayerRef
    var identity: StatsParticipant
    // 2. Volume
    var games: Int
    var rounds: Int
    var hours: Double
    var people: Int
    // 3. Record
    var wins: Int
    var winRate: Double
    /// Finishing position → games.
    var finishes: [Int: Int]
    /// Wins at or above an even share (1 / table size) count as "high" (WR-05).
    var isWinRateHigh: Bool
    // 4. Rating journey
    var ratingLine: [RatingPoint]
    var ratingStart: Int
    var ratingPeak: Int
    var ratingNow: Int
    var currentRank: Rank?
    // 5. Knocks
    var knocks: Int
    var knockSuccess: Double
    var favoriteKnockValue: Int?
    var bestKnock: KnockEvent?
    var worstKnock: KnockEvent?
    // 6. Nemesis and victim
    var nemesis: Person?
    var victim: Person?
    // 7. Card luck
    var redKings: Int
    var ghostHands: Int
    var biggestHand: Int
    // 8. The mouth
    var tauntsSent: Int
    var favoriteTaunt: TauntContent?
    var mostTaunted: Person?
    // 9. Titles and badges
    var badges: [BadgeAward]
    var titles: [TitleID]
    // 10. Hall of Shame
    var shame: [ShameEntry]
    // 11. Persona
    var persona: WrappedPersona
}

extension StatsSnapshot {
    /// The release date of a year's Wrapped: December 1 of that year.
    func wrappedRelease(for year: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: 12, day: 1)) ?? .distantFuture
    }

    func wrappedAvailability(for ref: PlayerRef, year: Int, now: Date = .now) -> WrappedAvailability {
        let played = record(ref)?.results(in: year, calendar: calendar).count ?? 0
        if played < WrappedSummary.minimumGames { return .needsGames(played: played, needed: WrappedSummary.minimumGames) }
        let release = wrappedRelease(for: year)
        return now >= release ? .available : .arrives(release)
    }

    /// The Wrapped a person should see now: this year's from December 1, otherwise last year's
    /// (it stays until the next one arrives).
    func currentWrappedYear(for ref: PlayerRef, now: Date = .now) -> Int? {
        let year = calendar.component(.year, from: now)
        for candidate in [year, year - 1] where wrappedAvailability(for: ref, year: candidate, now: now) == .available {
            return candidate
        }
        return nil
    }

    /// Builds a year's recap. nil with fewer than 10 games that year (the release date is the
    /// caller's to enforce, so previews and DEBUG can open it early).
    func wrapped(for ref: PlayerRef, year: Int, now: Date = .now) -> WrappedSummary? {
        let ref = options.canonical(ref)
        guard let record = record(ref) else { return nil }
        let results = record.results(in: year, calendar: calendar)
        guard results.count >= WrappedSummary.minimumGames else { return nil }
        let indices = Set(results.map(\.gameIndex))
        let yearGames = games.filter { indices.contains($0.index) }
        let knocks = record.knockEvents.filter { indices.contains($0.gameIndex) }
        let excluded = options.excluded

        // Volume
        let people = Set(yearGames.flatMap(\.refs)).subtracting([ref]).subtracting(excluded)
        let hours = yearGames.reduce(0) { $0 + $1.duration } / 3600

        // Record
        let wins = results.count(where: \.isWinner)
        let winRate = Double(wins) / Double(results.count)
        let evenShare = results.reduce(0.0) { $0 + 1 / Double(max(1, $1.playerCount)) } / Double(results.count)
        let finishes = Dictionary(grouping: results, by: { $0.rank.position }).mapValues(\.count)

        // Rating
        var line = [RatingPoint(gameIndex: (results.first?.gameIndex ?? 0) - 1, date: results.first?.date ?? now, rating: results.first?.ratingBefore ?? record.rating)]
        line += results.map { RatingPoint(gameIndex: $0.gameIndex, date: $0.date, rating: $0.ratingAfter) }
        let peak = line.map(\.rating).max() ?? record.rating

        // Knocks
        let landed = knocks.count { $0.outcome == .landed }
        let favorite = Dictionary(grouping: knocks, by: \.hand)
            .max { lhs, rhs in lhs.value.count != rhs.value.count ? lhs.value.count < rhs.value.count : lhs.key > rhs.key }?.key
        let best = knocks.filter { $0.outcome == .landed }.max { ($0.hand, -$0.gameIndex) < ($1.hand, -$1.gameIndex) }
        let worst = knocks.filter { $0.outcome == .failed }
            .max { ($0.hand - ($0.lowestOther ?? $0.hand), -$0.gameIndex) < ($1.hand - ($1.lowestOther ?? $1.hand), -$1.gameIndex) }

        // Nemesis and victim within the year
        var aheadOfMe: [PlayerRef: Int] = [:], iWasAhead: [PlayerRef: Int] = [:]
        for game in yearGames {
            let mine = game.totals[ref] ?? 0
            for other in game.refs where other != ref && !excluded.contains(other) {
                let theirs = game.totals[other] ?? 0
                if theirs < mine { aheadOfMe[other, default: 0] += 1 }
                if mine < theirs { iWasAhead[other, default: 0] += 1 }
            }
        }
        func top(_ counts: [PlayerRef: Int]) -> WrappedSummary.Person? {
            counts.max { lhs, rhs in lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.seatID > rhs.key.seatID }
                .map { WrappedSummary.Person(ref: $0.key, name: name(of: $0.key), count: $0.value) }
        }

        // The mouth
        let myTaunts = yearGames.flatMap(\.taunts).filter { $0.from == ref }
        let favoriteTaunt = Dictionary(grouping: myTaunts, by: \.content)
            .max { lhs, rhs in lhs.value.count < rhs.value.count }?.key
        let targets = Dictionary(grouping: myTaunts.compactMap(\.target).filter { !excluded.contains($0) }, by: { $0 }).mapValues(\.count)

        // Badges and titles this year
        let badges = record.badges.values
            .filter { award in award.date.map { calendar.component(.year, from: $0) == year } ?? false }
            .sorted { ($0.gameIndex ?? 0, $0.badge.rawValue) < ($1.gameIndex ?? 0, $1.badge.rawValue) }
        let unlocked = badges.compactMap { TitleID.unlocked(by: $0.badge) }
        let titles = TitleID.allCases.filter { Set(unlocked + heldTitles(of: ref, now: now)).contains($0) }

        let shame = shameEntries(of: ref, viewer: ref).filter { calendar.component(.year, from: $0.date) == year }

        return WrappedSummary(
            year: year, player: ref, identity: record.identity,
            games: results.count, rounds: results.reduce(0) { $0 + $1.roundsPlayed }, hours: hours, people: people.count,
            wins: wins, winRate: winRate, finishes: finishes, isWinRateHigh: winRate >= evenShare,
            ratingLine: line, ratingStart: Int((line.first?.rating ?? record.rating).rounded()), ratingPeak: Int(peak.rounded()),
            ratingNow: Int((line.last?.rating ?? record.rating).rounded()),
            currentRank: record.isRanked ? ratingRank(of: ref) : nil,
            knocks: knocks.count, knockSuccess: knocks.isEmpty ? 0 : Double(landed) / Double(knocks.count),
            favoriteKnockValue: favorite, bestKnock: best, worstKnock: worst,
            nemesis: top(aheadOfMe), victim: top(iWasAhead),
            redKings: results.reduce(0) { $0 + $1.redKings }, ghostHands: results.reduce(0) { $0 + $1.ghostHands },
            biggestHand: results.map(\.biggestHand).max() ?? 0,
            tauntsSent: myTaunts.count, favoriteTaunt: favoriteTaunt, mostTaunted: top(targets),
            badges: badges, titles: titles, shame: shame,
            persona: persona(for: ref, year: year)
        )
    }

    /// One of 8 archetypes: the first one the person tops among their people that year.
    func persona(for ref: PlayerRef, year: Int) -> WrappedPersona {
        let ref = options.canonical(ref)
        struct YearLine {
            var games = 0, rounds = 0, roundScore = 0, knocks = 0, landed = 0, beaten = 0, taunts = 0, comebacks = 0
        }
        var lines: [PlayerRef: YearLine] = [:]
        for person in circle(of: ref) {
            guard let record = records[person] else { continue }
            let results = record.results(in: year, calendar: calendar)
            guard results.count >= 5 else { continue }
            let indices = Set(results.map(\.gameIndex))
            let knocks = record.knockEvents.filter { indices.contains($0.gameIndex) }
            lines[person] = YearLine(
                games: results.count, rounds: results.reduce(0) { $0 + $1.roundsPlayed },
                roundScore: results.reduce(0) { $0 + $1.roundScoreSum }, knocks: knocks.count,
                landed: knocks.count { $0.outcome == .landed }, beaten: results.reduce(0) { $0 + $1.knocksBeaten },
                taunts: results.reduce(0) { $0 + $1.tauntsSent }, comebacks: results.count(where: \.isComeback)
            )
        }
        guard let mine = lines[ref], lines.count >= 2 else { return lines[ref] == nil ? .wildcard : .regular }

        func tops(_ metric: (YearLine) -> Double, minimum: Double, higher: Bool = true, eligible: (YearLine) -> Bool = { _ in true }) -> Bool {
            let pool = lines.values.filter(eligible)
            guard eligible(mine), metric(mine) >= minimum || !higher else { return false }
            let best = higher ? pool.map(metric).max() : pool.map(metric).min()
            return best.map { metric(mine) == $0 } ?? false
        }
        if tops({ Double($0.taunts) }, minimum: 10) { return .menace }
        if tops({ $0.knocks > 0 ? Double($0.landed) / Double($0.knocks) : 0 }, minimum: 0.5, eligible: { $0.knocks >= 10 }) { return .closer }
        if tops({ $0.rounds > 0 ? Double($0.knocks) / Double($0.rounds) : 0 }, minimum: 0.2) { return .gambler }
        if tops({ Double($0.beaten) }, minimum: 5) { return .snake }
        if tops({ Double($0.comebacks) }, minimum: 2) { return .comeback }
        if tops({ $0.rounds > 0 ? Double($0.roundScore) / Double($0.rounds) : .infinity }, minimum: 0, higher: false) { return .accountant }
        if tops({ Double($0.games) }, minimum: 10) { return .regular }
        return .wildcard
    }
}
