import Foundation

/// Hall of Shame categories (design §12.8, PRD §5.7): single moments only, never streaks.
nonisolated enum ShameCategory: String, Hashable, Sendable, CaseIterable, Identifiable {
    case worstHand, worstKnock, biggestLoss, bottleJob, ateIt, deepestHole

    var id: String { rawValue }

    /// Literal category name.
    var name: String {
        switch self {
        case .worstHand: "Worst Hand"
        case .worstKnock: "Worst Knock"
        case .biggestLoss: "Biggest Loss"
        case .bottleJob: "Bottle Job"
        case .ateIt: "Ate It"
        case .deepestHole: "Deepest Hole"
        }
    }

    /// The roast's copy ID.
    var copyID: String {
        switch self {
        case .worstHand: "HS-02"
        case .worstKnock: "HS-03"
        case .biggestLoss: "HS-04"
        case .bottleJob: "HS-05"
        case .ateIt: "HS-06"
        case .deepestHole: "HS-07"
        }
    }

    /// Ate It needs at least two failed knocks in a game to be a moment.
    var minimumValue: Int { self == .ateIt ? 2 : 1 }
}

/// Whose moments the Hall shows. There is no global Hall of Shame.
nonisolated enum ShameScope: String, Hashable, Sendable, CaseIterable, Identifiable {
    /// Everyone you've played with (the default).
    case yourPeople
    /// Only your own entries.
    case yours

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yourPeople: "Your people"
        case .yours: "Yours"
        }
    }
}

/// One shameful moment.
nonisolated struct ShameEntry: Hashable, Sendable, Identifiable {
    var category: ShameCategory
    var player: PlayerRef
    var identity: StatsParticipant
    var gameID: GameID
    var gameIndex: Int
    var tableWord: String
    var date: Date
    /// The round it happened in (nil for whole-game moments).
    var roundNumber: Int?
    /// The sort key: bigger is worse.
    var value: Int
    /// The knocker's hand (Worst Knock) or the hand (Worst Hand).
    var hand: Int?
    /// The lowest hand that beat the knock (Worst Knock).
    var low: Int?
    /// Where they finished (Bottle Job).
    var finish: Rank?

    var id: String { "\(category.rawValue)|\(gameID.uuidString)|\(player.seatID.rawValue)|\(roundNumber ?? 0)" }

    /// The literal numbers: "held 47", "knocked on 12 into a −1", "99 points", "up by 22, finished 3rd",
    /// "4 failed knocks", "41 back".
    var detail: String {
        switch category {
        case .worstHand: "held \(ScoreFormat.string(value))"
        case .worstKnock: "knocked on \(ScoreFormat.string(hand ?? 0)) into a \(ScoreFormat.string(low ?? 0))"
        case .biggestLoss: "\(ScoreFormat.string(value)) points"
        case .bottleJob: "up by \(value), finished \(finish?.ordinal ?? "behind")"
        case .ateIt: "\(value) failed knocks"
        case .deepestHole: "\(value) back"
        }
    }

    /// The roast's arguments for `category.copyID`.
    var roastArgs: VoiceArgs {
        switch category {
        case .worstHand: ["name": identity.name, "hand": value]
        case .worstKnock: ["hand": hand ?? 0, "low": low ?? 0]
        case .biggestLoss: ["score": value]
        case .bottleJob: ["gap": value]
        case .ateIt: ["n": value]
        case .deepestHole: ["gap": value]
        }
    }
}

/// One category's podium.
nonisolated struct ShameBoard: Hashable, Sendable, Identifiable {
    var category: ShameCategory
    /// Top 3, worst first. The first holds the cracked K.
    var entries: [ShameEntry]

    var id: ShameCategory { category }
}

extension StatsSnapshot {
    /// Players' first 3 games are learner games: they never produce entries for that player.
    static let learnerGames = 3

    /// Every candidate moment, one per (category, game, player): the worst of that game.
    func shameMoments() -> [ShameEntry] {
        var entries: [ShameEntry] = []
        for record in records.values {
            for result in record.results where result.gamesBefore >= Self.learnerGames {
                guard games.indices.contains(result.gameIndex) else { continue }
                let game = games[result.gameIndex]
                guard game.id == result.gameID else { continue }
                entries += moments(for: record, result: result, in: game)
            }
        }
        return entries
    }

    private func moments(for record: PlayerRecord, result: PlayerGameResult, in game: StatsGame) -> [ShameEntry] {
        let me = record.ref
        func entry(_ category: ShameCategory, value: Int, round: Int? = nil, hand: Int? = nil, low: Int? = nil, finish: Rank? = nil) -> ShameEntry? {
            guard value >= category.minimumValue else { return nil }
            let identity = game.participant(me) ?? record.identity
            return ShameEntry(
                category: category, player: me, identity: identity, gameID: game.id, gameIndex: game.index,
                tableWord: game.tableWord, date: game.finishedAt, roundNumber: round, value: value,
                hand: hand, low: low, finish: finish
            )
        }
        var output: [ShameEntry?] = []
        // Worst hand: the biggest single hand (earliest round on ties).
        if let worst = game.rounds.compactMap({ round in round.hands[me].map { (round.number, $0) } }).max(by: { ($0.1, -$0.0) < ($1.1, -$1.0) }) {
            output.append(entry(.worstHand, value: worst.1, round: worst.0, hand: worst.1))
        }
        // Worst knock: a failed knock with the biggest gap to the lowest hand.
        let failedKnocks = game.rounds.compactMap { round -> (Int, Int, Int)? in
            guard round.knocker == me, round.outcome == .failed, let hand = round.knockerHand, let low = round.lowestOtherHand else { return nil }
            return (round.number, hand, low)
        }
        if let worst = failedKnocks.max(by: { ($0.1 - $0.2, -$0.0) < ($1.1 - $1.2, -$1.0) }) {
            output.append(entry(.worstKnock, value: worst.1 - worst.2, round: worst.0, hand: worst.1, low: worst.2))
        }
        output.append(entry(.biggestLoss, value: result.finalScore))
        if !result.isWinner { output.append(entry(.bottleJob, value: result.biggestLead, finish: result.rank)) }
        output.append(entry(.ateIt, value: result.failed))
        output.append(entry(.deepestHole, value: result.deepestDeficit))
        return output.compactMap { $0 }
    }

    /// The Hall of Shame for a viewer: top 3 per category.
    ///
    /// - Parameters:
    ///   - viewer: Whose people to include. nil shows everyone on this phone (the game-end card for
    ///     a phone with no profile).
    func hallOfShame(scope: ShameScope = .yourPeople, viewer: PlayerRef?, limit: Int = 3) -> [ShameBoard] {
        let viewer = viewer.map(options.canonical)
        let allowed: Set<PlayerRef>? = switch (scope, viewer) {
        case (.yours, let viewer?): [viewer]
        case (.yourPeople, let viewer?): circle(of: viewer)
        case (_, nil): nil
        }
        let moments = shameMoments().filter { entry in
            !options.excluded.contains(entry.player) && (allowed?.contains(entry.player) ?? true)
        }
        let byCategory = Dictionary(grouping: moments, by: \.category)
        return ShameCategory.allCases.map { category in
            let sorted = (byCategory[category] ?? []).sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                // Ties: the earlier moment holds its place.
                if lhs.gameIndex != rhs.gameIndex { return lhs.gameIndex < rhs.gameIndex }
                return lhs.player.seatID < rhs.player.seatID
            }
            return ShameBoard(category: category, entries: Array(sorted.prefix(limit)))
        }
    }

    /// Every top-3 entry a person holds (profile "2 entries in the Hall of Shame").
    func shameEntries(of ref: PlayerRef, viewer: PlayerRef?) -> [ShameEntry] {
        let ref = options.canonical(ref)
        return hallOfShame(scope: .yourPeople, viewer: viewer ?? ref).flatMap(\.entries).filter { $0.player == ref }
    }

    /// Entries a game put into the top 3 (the game-end Hall of Shame card), among the viewer's people.
    func shameInductions(for game: GameID, viewer: PlayerRef?) -> [ShameEntry] {
        hallOfShame(scope: .yourPeople, viewer: viewer).flatMap(\.entries).filter { $0.gameID == game }
    }
}
