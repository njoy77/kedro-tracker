import Foundation

/// A badge's rim (design §12.6): Silver (most players), Red (10–40%), Gold (under 10%).
nonisolated enum BadgeTier: Int, Hashable, Sendable, Comparable, CaseIterable {
    case none, silver, red, gold

    static func < (lhs: BadgeTier, rhs: BadgeTier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Literal tier name for accessibility.
    var name: String {
        switch self {
        case .none: "No tier"
        case .silver: "Silver"
        case .red: "Red"
        case .gold: "Gold"
        }
    }
}

/// Badge categories, in grid order (design §12.6).
nonisolated enum BadgeCategory: String, Hashable, Sendable, CaseIterable, Identifiable {
    case milestone, knocking, cards, streaks, moments, rivalry, social, learning

    var id: String { rawValue }

    /// Literal section name.
    var name: String {
        switch self {
        case .milestone: "Milestones"
        case .knocking: "Knocking"
        case .cards: "Cards"
        case .streaks: "Streaks"
        case .moments: "Moments"
        case .rivalry: "Rivalry"
        case .social: "Social"
        case .learning: "Learning"
        }
    }

    /// The icon on the coin's rim.
    var systemImage: String {
        switch self {
        case .milestone: "flag.fill"
        case .knocking: "hand.raised.fill"
        case .cards: "suit.spade.fill"
        case .streaks: "flame.fill"
        case .moments: "bolt.fill"
        case .rivalry: "person.2.fill"
        case .social: "person.3.fill"
        case .learning: "book.fill"
        }
    }
}

/// Every badge (design §12.6). The raw value is the copy deck ID of its line (`BG-01`…`BG-34`),
/// which is also the badge's stable identifier.
nonisolated enum BadgeID: String, Hashable, Sendable, CaseIterable, Identifiable, Codable {
    case outOfTheGate = "BG-01"
    case firstBlood = "BG-02"
    case onTheBoard = "BG-03"
    case regular = "BG-04"
    case touchGrass = "BG-05"
    case topDog = "BG-06"
    case top100 = "BG-07"
    case landedIt = "BG-08"
    case foundOut = "BG-09"
    case deadHeat = "BG-10"
    case boldChoice = "BG-11"
    case hatTrick = "BG-12"
    case steadyHand = "BG-13"
    case belowZero = "BG-14"
    case ghostHand = "BG-15"
    case royalPair = "BG-16"
    case nothingToSeeHere = "BG-17"
    case fatStack = "BG-18"
    case threePeat = "BG-19"
    case untouchable = "BG-20"
    case comebackKid = "BG-21"
    case darkHorse = "BG-22"
    case neverTrailed = "BG-23"
    case byAHair = "BG-24"
    case sharedSpoils = "BG-25"
    case bottledIt = "BG-26"
    case nemesisTamed = "BG-27"
    case grudgeMatch = "BG-28"
    case exorcism = "BG-29"
    case playsWellWithOthers = "BG-30"
    case fullHouse = "BG-31"
    case badInfluence = "BG-32"
    case trashTalker = "BG-33"
    case didTheReading = "BG-34"

    var id: String { rawValue }

    /// The copy deck ID for the badge's line.
    var copyID: String { rawValue }

    var definition: BadgeDefinition { BadgeDefinition.catalog[self] ?? BadgeDefinition.fallback(self) }
}

/// What a badge is and how you get it.
nonisolated struct BadgeDefinition: Hashable, Sendable {
    var id: BadgeID
    /// Literal name ("Ghost Hand"), identical in every level.
    var name: String
    var category: BadgeCategory
    var tier: BadgeTier
    /// The literal rule, shown in Next up and the detail ("win 3 in a row").
    var rule: String
    /// Secret badges show as "?" until earned.
    var isSecret: Bool
    /// For counting badges: the target (25 games, 3 in a row). nil for one-off moments.
    var target: Int?

    static func fallback(_ id: BadgeID) -> BadgeDefinition {
        BadgeDefinition(id: id, name: id.rawValue, category: .milestone, tier: .silver, rule: "", isSecret: false, target: nil)
    }

    private static func make(_ id: BadgeID, _ name: String, _ category: BadgeCategory, _ tier: BadgeTier, _ rule: String, secret: Bool = false, target: Int? = nil) -> BadgeDefinition {
        BadgeDefinition(id: id, name: name, category: category, tier: tier, rule: rule, isSecret: secret, target: target)
    }

    /// All 34, in design order.
    static let all: [BadgeDefinition] = [
        make(.outOfTheGate, "Out of the Gate", .milestone, .silver, "finish your first game", target: 1),
        make(.firstBlood, "First Blood", .milestone, .silver, "win a game", target: 1),
        make(.onTheBoard, "On the Board", .milestone, .silver, "finish 5 games and get a rank", target: 5),
        make(.regular, "Regular", .milestone, .red, "finish 25 games", target: 25),
        make(.touchGrass, "Touch Grass", .milestone, .gold, "finish 100 games", target: 100),
        make(.topDog, "Top Dog", .milestone, .gold, "#1 by rating among your people (5+ ranked)"),
        make(.top100, "Top 100", .milestone, .gold, "global top 100 by rating"),
        make(.landedIt, "Landed It", .knocking, .silver, "land a knock"),
        make(.foundOut, "Found Out", .knocking, .silver, "fail a knock"),
        make(.deadHeat, "Dead Heat", .knocking, .silver, "tie a knock"),
        make(.boldChoice, "Bold Choice", .knocking, .silver, "knock on 10 or more and fail"),
        make(.hatTrick, "Hat Trick", .knocking, .red, "land 3 knocks in one game", target: 3),
        make(.steadyHand, "Steady Hand", .knocking, .gold, "land 10 knocks in a row", target: 10),
        make(.belowZero, "Below Zero", .cards, .red, "finish a round with a negative hand"),
        make(.ghostHand, "Ghost Hand", .cards, .red, "a hand of exactly 0"),
        make(.royalPair, "Royal Pair", .cards, .gold, "both red Kings in one hand"),
        make(.nothingToSeeHere, "Nothing to See Here", .cards, .gold, "land a knock on exactly 0", secret: true),
        make(.fatStack, "Fat Stack", .cards, .silver, "a hand of 40 or more"),
        make(.threePeat, "Three-Peat", .streaks, .red, "win 3 in a row", target: 3),
        make(.untouchable, "Untouchable", .streaks, .gold, "win 5 in a row", target: 5),
        make(.comebackKid, "Comeback Kid", .moments, .red, "win from outside the lead at halfway"),
        make(.darkHorse, "Dark Horse", .moments, .gold, "win against a table all rated higher"),
        make(.neverTrailed, "Never Trailed", .moments, .gold, "lead after every round of a 6+ round game, and win"),
        make(.byAHair, "By a Hair", .moments, .red, "win by exactly 1 point"),
        make(.sharedSpoils, "Shared Spoils", .moments, .red, "share a win"),
        make(.bottledIt, "Bottled It", .moments, .red, "lead into the final round, then lose", secret: true),
        make(.nemesisTamed, "Nemesis Tamed", .rivalry, .silver, "finish ahead of your nemesis"),
        make(.grudgeMatch, "Grudge Match", .rivalry, .red, "play the same rival 10 times", target: 10),
        make(.exorcism, "Exorcism", .rivalry, .gold, "finish ahead of your nemesis 3 straight times", secret: true),
        make(.playsWellWithOthers, "Plays Well With Others", .social, .silver, "play with 10 different people", target: 10),
        make(.fullHouse, "Full House", .social, .red, "finish an 8-player game"),
        make(.badInfluence, "Bad Influence", .social, .red, "a guest you played with makes an account and plays"),
        make(.trashTalker, "Trash Talker", .social, .silver, "send 50 taunts (3 a game count)", target: 50),
        make(.didTheReading, "Did the Reading", .learning, .none, "finish Learn and the Score a Round drill"),
    ]

    static let catalog: [BadgeID: BadgeDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The curated avatar a secret badge unlocks (design §12.6).
    var unlocksAvatar: CuratedAvatarID? {
        CuratedAvatarID.allCases.first { $0.unlockingBadge == name }
    }
}

/// A badge someone has, and the game that earned it.
nonisolated struct BadgeAward: Hashable, Sendable, Identifiable {
    var badge: BadgeID
    /// nil for Did the Reading (not earned at a table).
    var gameID: GameID?
    var tableWord: String?
    var roundNumber: Int?
    var date: Date?
    /// Replay position of the earning game.
    var gameIndex: Int?

    var id: BadgeID { badge }
    var definition: BadgeDefinition { badge.definition }
}

/// Progress toward an unearned counting badge (Next up).
nonisolated struct BadgeProgress: Hashable, Sendable, Identifiable {
    var badge: BadgeID
    var value: Int
    var target: Int

    var id: BadgeID { badge }
    var fraction: Double { target > 0 ? min(1, Double(value) / Double(target)) : 0 }
    var remaining: Int { max(0, target - value) }
    /// "1 of 3".
    var label: String { "\(min(value, target)) of \(target)" }
}

/// The curated avatars a person may pick: everything that isn't secret, plus the secrets their
/// badges unlocked (Exorcism → the Ghost, Nothing to See Here → the Hustler).
nonisolated enum AvatarUnlocks {
    static func available(earned: Set<BadgeID>) -> [CuratedAvatarID] {
        CuratedAvatarID.allCases.filter { avatar in
            guard let badgeName = avatar.unlockingBadge else { return true }
            return earned.contains { $0.definition.name == badgeName }
        }
    }
}
