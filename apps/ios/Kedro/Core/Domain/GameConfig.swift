import Foundation

/// How round results are entered (PRD §4.2). JSON: `"scorekeeper"` | `"selfReport"`.
nonisolated enum ScoringMode: String, Hashable, Sendable, Codable, CaseIterable {
    /// One person enters every hand.
    case scorekeeper
    /// Everyone reports their own hand; guests get an assigned reporter.
    case selfReport
}

/// Settings chosen in the lobby (design §5.6). Carried by `GameCreated`; later changes travel as
/// their own operations (`RoundsChanged`, `DealerChanged`, `ScorekeeperChanged`).
///
/// JSON: `{"plannedRounds":6,"scoringMode":"scorekeeper","tableWord":"Cold Deck",
///         "firstDealerSeat":"p:…","houseVoiceCap":"spicy","scorekeeperSeat":"p:…"}`
/// (optional keys are omitted when nil).
nonisolated struct GameConfig: Hashable, Sendable, Codable {
    /// Lobby presets (design §5.6); any value in `plannedRoundsRange` is allowed via Custom.
    static let roundPresets = [5, 6, 8, 10]
    static let plannedRoundsRange = 1...50
    /// PRD §4.1.
    static let seatRange = 3...8
    /// Default when there's no "last time's" value.
    static let defaultPlannedRounds = 6
    /// A finished game counts for stats, ratings and the leaderboard only with at least this many
    /// rounds, and a seat counts in it only if it played this many (a late joiner may not).
    static let countedMinimumRounds = 3

    var plannedRounds: Int
    var scoringMode: ScoringMode
    var tableWord: String
    /// Who deals Round 1. nil means the host (or the first seat).
    var firstDealerSeat: SeatID?
    /// The host can lower the house voice for the night, never raise it (design §4.1).
    var houseVoiceCap: LanguageLevel?
    /// Scorekeeper mode: whose phone enters the rounds. nil means the host.
    var scorekeeperSeat: SeatID?
    /// Set only by the server's web-history importer (its rounds keep the web's saved scores).
    var imported: Bool?

    init(
        plannedRounds: Int = GameConfig.defaultPlannedRounds,
        scoringMode: ScoringMode = .scorekeeper,
        tableWord: String = TableWord.random(),
        firstDealerSeat: SeatID? = nil,
        houseVoiceCap: LanguageLevel? = nil,
        scorekeeperSeat: SeatID? = nil,
        imported: Bool? = nil
    ) {
        self.plannedRounds = plannedRounds
        self.scoringMode = scoringMode
        self.tableWord = tableWord
        self.firstDealerSeat = firstDealerSeat
        self.houseVoiceCap = houseVoiceCap
        self.scorekeeperSeat = scorekeeperSeat
        self.imported = imported
    }
}

/// Two-word table names from a curated card-and-bar list (design §5.2). Shown in the Table header
/// and on the Table card, typed by hand for "Join with Code", and regenerable in the lobby.
nonisolated enum TableWord {
    static let all = [
        "Cold Deck", "Last Call", "Dead Hand", "Top Shelf", "Burnt Card", "Back Room",
        "Short Stack", "Wild Joker", "Red King", "Low Ball", "Blind Swap", "Dark Horse",
        "Night Cap", "Corner Booth", "Sticky Floor", "Bottom Deal", "Long Night", "Lucky Ace",
        "Crooked Cut", "Back Alley", "Smoke Break", "Late Deal", "Neat Pour", "Side Door",
        "Black Ace", "House Rules", "Loose Card", "Slow Hand", "Iron Joker", "Velvet Rope",
        "Cheap Seats", "Final Knock",
    ]

    static func random<G: RandomNumberGenerator>(using generator: inout G, excluding current: String? = nil) -> String {
        let pool = all.filter { $0 != current }
        return pool.randomElement(using: &generator) ?? "Cold Deck"
    }

    static func random(excluding current: String? = nil) -> String {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator, excluding: current)
    }

    /// Matches typed input ("cold deck", "COLD  DECK") to a table word; used by Join with Code.
    static func normalized(_ input: String) -> String {
        input.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
