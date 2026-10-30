import Foundation

/// Every title (design §12.7). The raw value is the copy deck ID (`TI-xx`); render the title with
/// `voice.line(id.rawValue)` in the **viewer's** level and the profile line with `taglineID`.
nonisolated enum TitleID: String, Hashable, Sendable, CaseIterable, Identifiable, Codable {
    case freshMeat = "TI-01"
    case regular = "TI-02"
    case untouchable = "TI-03"
    case theGhost = "TI-04"
    case royalty = "TI-05"
    case comebackKid = "TI-06"
    case darkHorse = "TI-07"
    case exorcist = "TI-08"
    case badInfluence = "TI-09"
    case stirrer = "TI-10"
    case touchGrass = "TI-11"
    case closer = "TI-12"
    case knockMerchant = "TI-13"
    case snake = "TI-14"
    case accountant = "TI-15"
    case redKingMagnet = "TI-16"
    case topDog = "TI-17"
    case bottler = "TI-18"

    var id: String { rawValue }
    var copyID: String { rawValue }
    var taglineID: String { rawValue + ".tagline" }

    enum Kind: Hashable, Sendable {
        /// Permanent once unlocked. `badge` nil means everyone has it (Fresh Meat).
        case earned(badge: BadgeID?)
        /// Recalculated after every finished game among your people; can be lost.
        case held(HeldMetric)
    }

    var kind: Kind {
        switch self {
        case .freshMeat: .earned(badge: nil)
        case .regular: .earned(badge: .regular)
        case .untouchable: .earned(badge: .untouchable)
        case .theGhost: .earned(badge: .ghostHand)
        case .royalty: .earned(badge: .royalPair)
        case .comebackKid: .earned(badge: .comebackKid)
        case .darkHorse: .earned(badge: .darkHorse)
        case .exorcist: .earned(badge: .exorcism)
        case .badInfluence: .earned(badge: .badInfluence)
        case .stirrer: .earned(badge: .trashTalker)
        case .touchGrass: .earned(badge: .touchGrass)
        case .closer: .held(.knockSuccess)
        case .knockMerchant: .held(.knockRate)
        case .snake: .held(.knocksBeaten)
        case .accountant: .held(.averageRound)
        case .redKingMagnet: .held(.redKingsThisYear)
        case .topDog: .held(.rating)
        case .bottler: .held(.bottledThisYear)
        }
    }

    var isHeld: Bool {
        if case .held = kind { true } else { false }
    }

    var heldMetric: HeldMetric? {
        if case .held(let metric) = kind { metric } else { nil }
    }

    var badge: BadgeID? {
        if case .earned(let badge) = kind { badge } else { nil }
    }

    /// The title a held title is earned against, or the title a badge unlocks.
    static func unlocked(by badge: BadgeID) -> TitleID? {
        allCases.first { $0.badge == badge }
    }

    /// When a displayed held title is lost, the player quietly switches to their best earned
    /// title: the rarest badge's title first, then catalog order (later = harder).
    var earnedRank: Int {
        let tier = badge?.definition.tier.rawValue ?? 0
        let order = Self.allCases.firstIndex(of: self) ?? 0
        return tier * 100 + order
    }
}

/// What a held title measures, with the minimum sample so nobody wins one in a lucky game
/// (design §12.7).
nonisolated enum HeldMetric: String, Hashable, Sendable, CaseIterable {
    /// The Closer: highest knock success, 15+ knocks.
    case knockSuccess
    /// Knock Merchant: highest knock rate, 50+ rounds.
    case knockRate
    /// The Snake: most times beating someone else's knock, 10+ games.
    case knocksBeaten
    /// The Accountant: lowest average round score, 20+ games.
    case averageRound
    /// Red King Magnet: most red Kings in final hands this year, 10+ games this year.
    case redKingsThisYear
    /// Top Dog: #1 by rating.
    case rating
    /// The Bottler: most final-round leads blown this year, 10+ games this year.
    case bottledThisYear

    var higherIsBetter: Bool { self != .averageRound }

    /// True when the metric resets every calendar year.
    var isYearly: Bool { self == .redKingsThisYear || self == .bottledThisYear }

    /// Whether a record has a big enough sample to hold the title (in `year` for yearly ones).
    func qualifies(_ record: PlayerRecord, year: Int, calendar: Calendar) -> Bool {
        guard record.isRanked else { return false }
        switch self {
        case .knockSuccess: return record.knocks >= 15
        case .knockRate: return record.roundsPlayed >= 50
        case .knocksBeaten: return record.gamesPlayed >= 10 && record.knocksBeaten > 0
        case .averageRound: return record.gamesPlayed >= 20
        case .rating: return true
        case .redKingsThisYear:
            let games = record.results(in: year, calendar: calendar)
            return games.count >= 10 && games.reduce(0) { $0 + $1.redKings } > 0
        case .bottledThisYear:
            let games = record.results(in: year, calendar: calendar)
            return games.count >= 10 && games.contains(where: \.bottledFinalRound)
        }
    }

    /// The metric value (compare with `higherIsBetter`).
    func value(_ record: PlayerRecord, year: Int, calendar: Calendar) -> Double {
        switch self {
        case .knockSuccess: record.knockSuccessRate ?? 0
        case .knockRate: record.knockRate ?? 0
        case .knocksBeaten: Double(record.knocksBeaten)
        case .averageRound: record.averageRoundScore ?? .infinity
        case .rating: record.rating
        case .redKingsThisYear: Double(record.results(in: year, calendar: calendar).reduce(0) { $0 + $1.redKings })
        case .bottledThisYear: Double(record.results(in: year, calendar: calendar).count(where: \.bottledFinalRound))
        }
    }

    /// The replay index at which the record reached its current value ("got there first").
    func reachedAt(_ record: PlayerRecord, year: Int, calendar: Calendar) -> Int {
        switch self {
        case .redKingsThisYear:
            record.results(in: year, calendar: calendar).last { $0.redKings > 0 }?.gameIndex ?? .max
        case .bottledThisYear:
            record.results(in: year, calendar: calendar).last(where: \.bottledFinalRound)?.gameIndex ?? .max
        default:
            record.metricChangedAt[self] ?? .max
        }
    }
}

extension PlayerRecord {
    nonisolated func results(in year: Int, calendar: Calendar) -> [PlayerGameResult] {
        results.filter { calendar.component(.year, from: $0.date) == year }
    }
}
