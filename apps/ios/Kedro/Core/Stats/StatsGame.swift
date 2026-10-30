import Foundation

/// Options that shape how history is read (PRD §5: everything is derived, so these are inputs,
/// never stored counters).
nonisolated struct StatsOptions: Hashable, Sendable {
    /// Claimed guest identities → the account that claimed them (PRD §3.2). A claimed guest's
    /// games count as the account's from game 1, so ratings, badges and records come out right.
    var aliases: [PlayerRef: PlayerRef] = [:]
    /// People the viewer has blocked (or who blocked them): hidden from boards, the Hall of Shame,
    /// Wrapped and rivals. Ratings still replay every game.
    var excluded: Set<PlayerRef> = []
    /// People who finished Learn and the Score a Round drill (Did the Reading).
    var didTheReading: Set<PlayerRef> = []

    init(aliases: [PlayerRef: PlayerRef] = [:], excluded: Set<PlayerRef> = [], didTheReading: Set<PlayerRef> = []) {
        self.aliases = aliases
        self.excluded = excluded
        self.didTheReading = didTheReading
    }

    /// The identity a seat counts as.
    func canonical(_ ref: PlayerRef) -> PlayerRef { aliases[ref] ?? ref }
}

/// One person at one finished game, as stats see them.
nonisolated struct StatsParticipant: Hashable, Sendable {
    /// The identity stats are credited to (a claimed guest maps to the account).
    var ref: PlayerRef
    /// The identity in the seat at the time (a guest before a claim).
    var seatedAs: PlayerRef
    var name: String
    var avatar: Avatar?
    var handle: Handle?
    var titleID: String?
}

/// One saved round keyed by person rather than seat.
nonisolated struct StatsRound: Hashable, Sendable {
    var number: Int
    var hands: [PlayerRef: Int]
    var knocker: PlayerRef
    var scores: [PlayerRef: Int]
    var outcome: KnockOutcome?

    init(number: Int, hands: [PlayerRef: Int], knocker: PlayerRef) {
        self.number = number
        self.hands = hands
        self.knocker = knocker
        scores = Scoring.roundScores(hands: hands, knocker: knocker)
        outcome = Scoring.knockOutcome(hands: hands, knocker: knocker)
    }

    var knockerHand: Int? { hands[knocker] }

    /// The lowest hand among everyone but the knocker.
    var lowestOtherHand: Int? { hands.filter { $0.key != knocker }.values.min() }
}

/// A taunt that counts for stats (not retracted).
nonisolated struct StatsTaunt: Hashable, Sendable {
    var from: PlayerRef
    var target: PlayerRef?
    var content: TauntContent
}

/// A finished, non-abandoned game normalized for stats: people instead of seats, claims applied,
/// cumulative totals after every round precomputed.
nonisolated struct StatsGame: Hashable, Sendable, Identifiable {
    let id: GameID
    /// Position in the chronological replay (0 = oldest).
    var index: Int
    var tableWord: String
    var startedAt: Date?
    var finishedAt: Date
    var finishReason: FinishReason?
    /// Seat order.
    var participants: [StatsParticipant]
    var rounds: [StatsRound]
    /// Running totals after each round (`cumulative[r]` is after round r + 1).
    var cumulative: [[PlayerRef: Int]]
    var totals: [PlayerRef: Int]
    var ranks: [PlayerRef: Rank]
    var winners: Set<PlayerRef>
    var taunts: [StatsTaunt]

    var refs: [PlayerRef] { participants.map(\.ref) }
    var playerCount: Int { participants.count }

    func participant(_ ref: PlayerRef) -> StatsParticipant? { participants.first { $0.ref == ref } }

    func contains(_ ref: PlayerRef) -> Bool { participants.contains { $0.ref == ref } }

    /// Best first; equal totals keep seat order.
    var finishingOrder: [PlayerRef] { Scoring.ordered(totals, tieOrder: refs) }

    /// Time at the table, start to finish.
    var duration: TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, finishedAt.timeIntervalSince(startedAt))
    }

    /// Leaders (lowest running total, ties share) after a round (1-based).
    func leaders(afterRound round: Int) -> Set<PlayerRef> {
        guard round >= 1, round <= cumulative.count else { return [] }
        return Scoring.winners(cumulative[round - 1])
    }

    /// Builds the stats view of a folded game. Returns nil unless the game is finished.
    init?(state: GameState, index: Int, options: StatsOptions) {
        guard state.status == .finished, !state.rounds.isEmpty else { return nil }
        id = state.gameID
        self.index = index
        tableWord = state.config.tableWord
        startedAt = state.startedAt ?? state.createdAt
        finishedAt = state.finishedAt ?? state.latestHLC?.date ?? state.createdAt ?? .distantPast
        finishReason = state.finishReason

        participants = state.seats.map { seat in
            StatsParticipant(
                ref: options.canonical(seat.player), seatedAs: seat.player, name: seat.displayName,
                avatar: seat.avatar, handle: seat.handle, titleID: seat.titleID
            )
        }
        let map = Dictionary(state.seats.map { ($0.id, options.canonical($0.player)) }, uniquingKeysWith: { first, _ in first })
        func person(_ seat: SeatID) -> PlayerRef { map[seat] ?? options.canonical(seat.playerRef) }

        rounds = state.rounds.map { record in
            let hands = Dictionary(record.round.hands.map { (person($0.key), $0.value) }, uniquingKeysWith: +)
            return StatsRound(number: record.number, hands: hands, knocker: person(record.knocker))
        }
        var running: [PlayerRef: Int] = Dictionary(uniqueKeysWithValues: participants.map { ($0.ref, 0) })
        var cumulative: [[PlayerRef: Int]] = []
        for round in rounds {
            for (ref, score) in round.scores { running[ref, default: 0] += score }
            cumulative.append(running)
        }
        self.cumulative = cumulative
        totals = running
        ranks = Scoring.ranks(running)
        winners = Scoring.winners(running)
        taunts = state.visibleTaunts.compactMap { taunt in
            guard let from = taunt.from else { return nil }
            let target: PlayerRef? = if case .seat(let seat) = taunt.target { person(seat) } else { nil }
            return StatsTaunt(from: person(from), target: target, content: taunt.content)
        }
    }

    /// Normalizes and orders a store's finished games (oldest first, ties by game ID).
    static func normalize(_ states: [GameState], options: StatsOptions) -> [StatsGame] {
        let finished = states
            .filter { $0.status == .finished && !$0.rounds.isEmpty }
            .sorted { lhs, rhs in
                let left = lhs.finishedAt ?? lhs.latestHLC?.date ?? .distantPast
                let right = rhs.finishedAt ?? rhs.latestHLC?.date ?? .distantPast
                if left != right { return left < right }
                return lhs.gameID.uuidString < rhs.gameID.uuidString
            }
        var seen: Set<GameID> = []
        var games: [StatsGame] = []
        for state in finished where seen.insert(state.gameID).inserted {
            if let game = StatsGame(state: state, index: games.count, options: options) {
                games.append(game)
            }
        }
        return games
    }
}

/// Inferred card facts. Kedro records hand values, not cards, so these are lower bounds read from
/// the value: −2 can only be both red Kings, −1 needs at least one (PRD §2.2).
nonisolated enum CardInference {
    static func redKings(inHand hand: Int) -> Int {
        switch hand {
        case ...(-2): 2
        case -1: 1
        default: 0
        }
    }
}
