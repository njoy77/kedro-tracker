import Foundation

/// Every stat, rating, badge and record, derived by replaying finished games in order
/// (PRD §5: derived, never stored). Build one with `StatsSnapshot.build(_:options:)` from
/// `GameStore.finishedGames()`; it's a value, so it can be built off the main actor.
///
/// Query it through the extensions: `stats(for:)`, `headToHead(_:_:)`, `leaderboard(...)`,
/// `records(...)`, `badges(for:)`, `heldTitles(...)`, `hallOfShame(...)`, `wrapped(...)`,
/// `gameEnd(for:)`.
nonisolated struct StatsSnapshot: Sendable {
    let options: StatsOptions
    /// Oldest first; `games[i].index == i`.
    let games: [StatsGame]
    let records: [PlayerRef: PlayerRecord]
    /// Rating changes by game.
    let ratingChanges: [GameID: [PlayerRef: RatingChange]]
    /// Badges earned by game (the game-end "Badges earned" card).
    let badgesEarned: [GameID: [PlayerRef: [BadgeAward]]]
    /// Rating after every game, per player, oldest first.
    let ratingHistory: [PlayerRef: [RatingPoint]]
    let calendar: Calendar

    static let empty = StatsSnapshot(games: [], options: StatsOptions())

    /// Builds a snapshot from folded games (any order; non-finished ones are ignored).
    static func build(_ states: [GameState], options: StatsOptions = StatsOptions(), calendar: Calendar = .kedro) -> StatsSnapshot {
        StatsSnapshot(games: StatsGame.normalize(states, options: options), options: options, calendar: calendar)
    }

    /// Builds off the main actor.
    @concurrent
    static func buildInBackground(_ states: [GameState], options: StatsOptions = StatsOptions()) async -> StatsSnapshot {
        build(states, options: options)
    }

    /// The same history up to (not including) a game: what everyone looked like before it.
    func before(_ game: GameID) -> StatsSnapshot {
        guard let index = games.firstIndex(where: { $0.id == game }) else { return self }
        return StatsSnapshot(games: Array(games.prefix(index)), options: options, calendar: calendar)
    }

    /// The history as it stood at a moment (games finished at or before `date`).
    func asOf(_ date: Date) -> StatsSnapshot {
        StatsSnapshot(games: games.filter { $0.finishedAt <= date }, options: options, calendar: calendar)
    }

    func game(_ id: GameID) -> StatsGame? { games.first { $0.id == id } }

    func record(_ ref: PlayerRef) -> PlayerRecord? { records[options.canonical(ref)] }

    // MARK: Replay

    init(games: [StatsGame], options: StatsOptions, calendar: Calendar = .kedro) {
        self.options = options
        self.calendar = calendar
        // Re-index so prefixes and filtered lists stay consistent.
        let games = games.enumerated().map { offset, game in
            var game = game
            game.index = offset
            return game
        }
        self.games = games

        var records: [PlayerRef: PlayerRecord] = [:]
        var ratingChanges: [GameID: [PlayerRef: RatingChange]] = [:]
        var badgesEarned: [GameID: [PlayerRef: [BadgeAward]]] = [:]
        var ratingHistory: [PlayerRef: [RatingPoint]] = [:]

        for game in games {
            for participant in game.participants where records[participant.ref] == nil {
                records[participant.ref] = PlayerRecord(ref: participant.ref, identity: participant)
            }
            let refs = game.refs
            let before = Dictionary(refs.map { ($0, records[$0]?.rating ?? Ratings.startingRating) }, uniquingKeysWith: { first, _ in first })
            let gamesBefore = Dictionary(refs.map { ($0, records[$0]?.gamesPlayed ?? 0) }, uniquingKeysWith: { first, _ in first })
            let deltas = Ratings.deltas(totals: game.totals, ratings: before, gamesBefore: gamesBefore, order: refs)
            // Rivalry context from before the game.
            let nemesisBefore = Dictionary(refs.map { ($0, records[$0]?.nemesis(accountsOnly: true)?.ref) }, uniquingKeysWith: { first, _ in first })

            var changes: [PlayerRef: RatingChange] = [:]
            for participant in game.participants {
                guard var record = records[participant.ref] else { continue }
                let ref = participant.ref
                let ratingBefore = before[ref] ?? Ratings.startingRating
                let ratingAfter = ratingBefore + (deltas[ref] ?? 0)
                Self.apply(game: game, participant: participant, to: &record, ratingBefore: ratingBefore, ratingAfter: ratingAfter)
                changes[ref] = RatingChange(player: ref, before: ratingBefore, after: ratingAfter, gamesBefore: gamesBefore[ref] ?? 0)
                ratingHistory[ref, default: []].append(RatingPoint(gameIndex: game.index, date: game.finishedAt, rating: ratingAfter))
                records[ref] = record
            }
            ratingChanges[game.id] = changes

            // Badges, with everyone's post-game state in hand.
            var earnedHere: [PlayerRef: [BadgeAward]] = [:]
            for ref in refs {
                let awards = BadgeEvaluator.evaluate(
                    ref, in: game, records: records, ratingsBefore: before, nemesisBefore: nemesisBefore[ref] ?? nil
                )
                for award in awards where records[ref]?.badges[award.badge] == nil {
                    records[ref]?.badges[award.badge] = award
                    earnedHere[ref, default: []].append(award)
                }
            }
            for (ref, award) in BadgeEvaluator.badInfluence(in: game, records: records) where records[ref]?.badges[.badInfluence] == nil {
                records[ref]?.badges[.badInfluence] = award
                earnedHere[ref, default: []].append(award)
            }
            if !earnedHere.isEmpty { badgesEarned[game.id] = earnedHere }
        }

        for ref in options.didTheReading {
            let ref = options.canonical(ref)
            guard records[ref] != nil, records[ref]?.badges[.didTheReading] == nil else { continue }
            records[ref]?.badges[.didTheReading] = BadgeAward(badge: .didTheReading)
        }

        self.records = records
        self.ratingChanges = ratingChanges
        self.badgesEarned = badgesEarned
        self.ratingHistory = ratingHistory
    }

    /// Folds one game into one person's record.
    private static func apply(game: StatsGame, participant: StatsParticipant, to record: inout PlayerRecord, ratingBefore: Double, ratingAfter: Double) {
        let me = participant.ref
        let myTotal = game.totals[me] ?? 0
        let isWinner = game.winners.contains(me)
        let rounds = game.rounds
        let previous = (
            knockSuccess: record.knockSuccessRate, knockRate: record.knockRate,
            beaten: record.knocksBeaten, average: record.averageRoundScore, rating: record.rating
        )

        var knocks = 0, landed = 0, tied = 0, failed = 0, beaten = 0, redKings = 0, ghosts = 0, inherentKnocks = 0, inherentLanded = 0
        var biggestHand = Int.min, roundsPlayed = 0, roundScoreSum = 0
        for round in rounds {
            guard let hand = round.hands[me] else { continue }
            roundsPlayed += 1
            roundScoreSum += round.scores[me] ?? hand
            redKings += CardInference.redKings(inHand: hand)
            if hand == 0 { ghosts += 1 }
            biggestHand = max(biggestHand, hand)
            if round.inherent == me {
                inherentKnocks += 1
                if round.isInherentKnock, round.outcome == .landed { inherentLanded += 1 }
            }
            if round.regularKnocker == me, let outcome = round.outcome {
                knocks += 1
                switch outcome {
                case .landed:
                    landed += 1
                    record.currentLandedStreak += 1
                    record.longestLandedStreak = max(record.longestLandedStreak, record.currentLandedStreak)
                case .tied, .noPenalty:
                    tied += 1
                    record.currentLandedStreak = 0
                case .failed:
                    failed += 1
                    record.currentLandedStreak = 0
                }
                record.knockEvents.append(KnockEvent(
                    gameID: game.id, gameIndex: game.index, date: game.finishedAt, tableWord: game.tableWord,
                    roundNumber: round.number, hand: hand, lowestOther: round.lowestOtherHand, outcome: outcome
                ))
            } else if round.outcome == .failed, let knockerHand = round.knockerHand, hand < knockerHand {
                beaten += 1
            }
        }

        // Leads and holes.
        let half = rounds.count / 2
        let ledAtHalf = half >= 1 && game.leaders(afterRound: half).contains(me)
        var biggestLead = 0, deepest = 0
        for totals in game.cumulative {
            guard let mine = totals[me] else { continue }
            let others = totals.filter { $0.key != me }.values
            if let bestOther = others.min(), mine < bestOther { biggestLead = max(biggestLead, bestOther - mine) }
            if let best = totals.values.min() { deepest = max(deepest, mine - best) }
        }
        let bottled = rounds.count >= 2 && game.leaders(afterRound: rounds.count - 1) == [me] && !isWinner

        let taunts = game.taunts.count { $0.from == me }
        let result = PlayerGameResult(
            gameID: game.id, gameIndex: game.index, date: game.finishedAt, tableWord: game.tableWord,
            playerCount: game.playerCount, finalScore: myTotal, rank: game.ranks[me] ?? Rank(position: game.playerCount, isShared: false),
            isWinner: isWinner, isSharedWin: isWinner && game.winners.count > 1,
            roundsPlayed: roundsPlayed, roundScoreSum: roundScoreSum,
            knocks: knocks, landed: landed, tied: tied, failed: failed, knocksBeaten: beaten,
            inherentKnocks: inherentKnocks, inherentKnocksLanded: inherentLanded,
            redKings: redKings, ghostHands: ghosts, biggestHand: biggestHand == .min ? 0 : biggestHand,
            isComeback: isWinner && half >= 1 && !ledAtHalf, bottledFinalRound: bottled,
            biggestLead: biggestLead, deepestDeficit: deepest,
            ratingBefore: ratingBefore, ratingAfter: ratingAfter,
            tauntsSent: taunts, tauntsCounted: min(3, taunts), gamesBefore: record.gamesPlayed
        )
        record.results.append(result)
        record.identity = participant
        record.rating = ratingAfter

        if isWinner {
            record.currentWinStreak += 1
            record.longestWinStreak = max(record.longestWinStreak, record.currentWinStreak)
        } else {
            record.currentWinStreak = 0
        }

        for other in game.participants where other.ref != me {
            let them = other.ref
            let theirTotal = game.totals[them] ?? 0
            record.sharedGames[them, default: 0] += 1
            if theirTotal < myTotal {
                record.finishedAheadOfMe[them, default: 0] += 1
                record.finishedAheadOfMeAt[them] = game.index
            }
            if myTotal < theirTotal {
                record.iFinishedAhead[them, default: 0] += 1
                record.iFinishedAheadAt[them] = game.index
                record.aheadStreak[them, default: 0] += 1
            } else {
                record.aheadStreak[them] = 0
            }
            if participant.seatedAs.isGuest, !participant.ref.isGuest {
                record.guestEraCompanions.insert(them)
            }
        }

        // When each held metric last changed ("ties go to whoever got there first").
        func mark(_ metric: HeldMetric, _ changed: Bool) {
            if changed || record.metricChangedAt[metric] == nil { record.metricChangedAt[metric] = game.index }
        }
        mark(.knockSuccess, previous.knockSuccess != record.knockSuccessRate)
        mark(.knockRate, previous.knockRate != record.knockRate)
        mark(.knocksBeaten, previous.beaten != record.knocksBeaten)
        mark(.averageRound, previous.average != record.averageRoundScore)
        mark(.rating, previous.rating != record.rating)
    }

    // MARK: People

    /// Everyone a person has shared a finished game with (not including them).
    func people(of ref: PlayerRef) -> Set<PlayerRef> {
        Set((record(ref)?.sharedGames.keys).map(Array.init) ?? []).subtracting(options.excluded)
    }

    /// The person and everyone they've played with.
    func circle(of ref: PlayerRef) -> Set<PlayerRef> {
        people(of: ref).union([options.canonical(ref)])
    }

    /// Lifetime stats (PRD §5.1). nil if the person has no finished games.
    func stats(for ref: PlayerRef) -> PlayerStats? {
        record(ref).map { PlayerStats(record: $0, excluded: options.excluded) }
    }

    /// The latest name and avatar seen for a person.
    func identity(of ref: PlayerRef) -> StatsParticipant? { record(ref)?.identity }

    func name(of ref: PlayerRef) -> String { identity(of: ref)?.name ?? "Someone" }

    /// Rating changes for one game.
    func ratingChanges(for game: GameID) -> [PlayerRef: RatingChange] { ratingChanges[game] ?? [:] }
}

extension Calendar {
    /// Gregorian in the phone's time zone: years for Wrapped and the yearly titles.
    nonisolated static var kedro: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}
