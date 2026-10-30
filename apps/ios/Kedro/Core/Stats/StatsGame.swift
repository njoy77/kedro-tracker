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
    /// Rounds a game needs to count, and a seat needs to have played to count in it. Always
    /// `GameConfig.countedMinimumRounds` in the app; tests with one-round fixtures lower it.
    var minimumRounds = GameConfig.countedMinimumRounds

    init(aliases: [PlayerRef: PlayerRef] = [:], excluded: Set<PlayerRef> = [], didTheReading: Set<PlayerRef> = []) {
        self.aliases = aliases
        self.excluded = excluded
        self.didTheReading = didTheReading
    }

    /// Whether a folded game counts (`GameState.countsForStats` at the app's threshold).
    func counts(_ state: GameState) -> Bool {
        state.status == .finished && state.rounds.count >= minimumRounds
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

    /// A round whose scores were already worked out by seat (the game's own scoring), keyed by
    /// person after the fact. Used when a seat is dropped as a duplicate of the same person, so
    /// the remaining seats keep the scores they actually got at the table.
    init(number: Int, hands: [PlayerRef: Int], knocker: PlayerRef, scores: [PlayerRef: Int], outcome: KnockOutcome?) {
        self.number = number
        self.hands = hands
        self.knocker = knocker
        self.scores = scores
        self.outcome = outcome
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

    /// Builds the stats view of a folded game. Returns nil unless it counts (`StatsOptions.counts`).
    init?(state: GameState, index: Int, options: StatsOptions) {
        guard options.counts(state) else { return nil }
        id = state.gameID
        self.index = index
        tableWord = state.config.tableWord
        startedAt = state.startedAt ?? state.createdAt
        finishedAt = state.finishedAt ?? state.latestHLC?.date ?? state.createdAt ?? .distantPast
        finishReason = state.finishReason

        // One participant per person. A claimed guest seated beside the account that later
        // claimed it counts once, as the account's own seat (the server's ratedGames does the
        // same), so its hands and score are dropped instead of being merged in. A late joiner
        // who played fewer than 3 rounds doesn't count either.
        let played = state.rounds.reduce(into: [SeatID: Int]()) { counts, record in
            for seat in record.round.hands.keys { counts[seat, default: 0] += 1 }
        }
        let counted = Self.countedSeats(state.seats, options: options)
            .filter { played[$0.id, default: 0] >= options.minimumRounds }
        participants = counted.map { seat in
            StatsParticipant(
                ref: options.canonical(seat.player), seatedAs: seat.player, name: seat.displayName,
                avatar: seat.avatar, handle: seat.handle, titleID: seat.titleID
            )
        }
        let countedIDs = Set(counted.map(\.id))
        let map = Dictionary(state.seats.map { ($0.id, options.canonical($0.player)) }, uniquingKeysWith: { first, _ in first })
        func person(_ seat: SeatID) -> PlayerRef { map[seat] ?? options.canonical(seat.playerRef) }

        rounds = state.rounds.map { record in
            if countedIDs.count == state.seats.count {
                let hands = Dictionary(record.round.hands.map { (person($0.key), $0.value) }, uniquingKeysWith: +)
                return StatsRound(number: record.number, hands: hands, knocker: person(record.knocker))
            }
            let hands = Dictionary(
                record.round.hands.filter { countedIDs.contains($0.key) }.map { (person($0.key), $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
            let scores = Dictionary(
                record.scores.filter { countedIDs.contains($0.key) }.map { (person($0.key), $0.value) },
                uniquingKeysWith: { first, _ in first }
            )
            return StatsRound(number: record.number, hands: hands, knocker: person(record.knocker), scores: scores, outcome: record.outcome)
        }
        // Late joiners enter the running totals at their starting score on their first round.
        let lateStarts = counted.filter { $0.firstRound > 1 }
        var running: [PlayerRef: Int] = Dictionary(
            participants.filter { participant in !lateStarts.contains { options.canonical($0.player) == participant.ref } }.map { ($0.ref, 0) },
            uniquingKeysWith: { first, _ in first }
        )
        var cumulative: [[PlayerRef: Int]] = []
        for round in rounds {
            for seat in lateStarts where seat.firstRound == round.number {
                running[options.canonical(seat.player)] = seat.startingScore ?? 0
            }
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

    /// The seats that count, in seat order: the first seat for each person, preferring a seat
    /// held under the person's own identity over one that maps to them through a claim.
    static func countedSeats(_ seats: [Seat], options: StatsOptions) -> [Seat] {
        var chosen: [PlayerRef: Seat] = [:]
        for seat in seats {
            let ref = options.canonical(seat.player)
            guard let existing = chosen[ref] else {
                chosen[ref] = seat
                continue
            }
            if existing.player != ref, seat.player == ref { chosen[ref] = seat }
        }
        let keep = Set(chosen.values.map(\.id))
        return seats.filter { keep.contains($0.id) }
    }

    /// Normalizes and orders a store's finished games (oldest first, ties by game ID).
    static func normalize(_ states: [GameState], options: StatsOptions) -> [StatsGame] {
        let finished = states
            .filter(options.counts)
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
