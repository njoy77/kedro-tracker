import Foundation

/// Badge rules (design §12.6). Badges are evaluated at game finish only (and so on guest claims,
/// which replay the claimed games), from each person's record right after the game.
///
/// Anti-farming: social and rivalry badges count only accounts and claimed guests, and only
/// finished, non-abandoned games (the only games stats ever see).
nonisolated enum BadgeEvaluator {
    /// Top 100 needs a real global board: with fewer ranked players than this, the badge would
    /// mean nothing, so it isn't awarded from on-phone history.
    static let top100MinimumBoard = 101

    /// Badges a person qualifies for after a game (already-earned ones are filtered by the caller).
    static func evaluate(
        _ me: PlayerRef,
        in game: StatsGame,
        records: [PlayerRef: PlayerRecord],
        ratingsBefore: [PlayerRef: Double],
        nemesisBefore: PlayerRef?
    ) -> [BadgeAward] {
        guard let record = records[me], let result = record.results.last, result.gameID == game.id else { return [] }
        var awards: [BadgeAward] = []
        func award(_ badge: BadgeID, round: Int? = nil) {
            guard record.badges[badge] == nil else { return }
            awards.append(BadgeAward(
                badge: badge, gameID: game.id, tableWord: game.tableWord, roundNumber: round,
                date: game.finishedAt, gameIndex: game.index
            ))
        }

        // Milestones
        if record.gamesPlayed >= 1 { award(.outOfTheGate) }
        if record.wins >= 1 { award(.firstBlood) }
        if record.gamesPlayed >= 5 { award(.onTheBoard) }
        if record.gamesPlayed >= 25 { award(.regular) }
        if record.gamesPlayed >= 100 { award(.touchGrass) }
        if isTopDog(me, records: records) { award(.topDog) }
        if isTop100(me, records: records) { award(.top100) }

        // Knocking and cards, round by round
        let myRounds = game.rounds.filter { $0.hands[me] != nil }
        var landedSoFar = 0
        var streak = preGameLandedStreak(record, game: game.id)
        for round in myRounds {
            guard let hand = round.hands[me] else { continue }
            if round.regularKnocker == me, let outcome = round.outcome {
                switch outcome {
                case .landed:
                    award(.landedIt, round: round.number)
                    landedSoFar += 1
                    streak += 1
                    if landedSoFar >= 3 { award(.hatTrick, round: round.number) }
                    if streak >= 10 { award(.steadyHand, round: round.number) }
                    if hand == 0 { award(.nothingToSeeHere, round: round.number) }
                case .tied:
                    award(.deadHeat, round: round.number)
                    streak = 0
                case .failed:
                    award(.foundOut, round: round.number)
                    if hand >= 10 { award(.boldChoice, round: round.number) }
                    streak = 0
                case .noPenalty:
                    break // only inherent knocks get this, and they aren't regular knocks
                }
            }
            if hand < 0 { award(.belowZero, round: round.number) }
            if hand == 0 { award(.ghostHand, round: round.number) }
            if hand <= -2 { award(.royalPair, round: round.number) }
            if hand >= 40 { award(.fatStack, round: round.number) }
        }

        // Streaks
        if record.currentWinStreak >= 3 { award(.threePeat) }
        if record.currentWinStreak >= 5 { award(.untouchable) }

        // Moments
        if result.isWinner {
            if result.isComeback { award(.comebackKid) }
            let mine = ratingsBefore[me] ?? Ratings.startingRating
            let opponents = game.refs.filter { $0 != me }
            if !opponents.isEmpty, opponents.allSatisfy({ (ratingsBefore[$0] ?? Ratings.startingRating) > mine }) {
                award(.darkHorse)
            }
            if game.rounds.count >= 6, (1...game.rounds.count).allSatisfy({ game.leaders(afterRound: $0).contains(me) }) {
                award(.neverTrailed)
            }
            if game.winners.count == 1 {
                let others = game.totals.filter { $0.key != me }.values
                if let second = others.min(), second - result.finalScore == 1 { award(.byAHair) }
            } else {
                award(.sharedSpoils)
            }
        }
        if result.bottledFinalRound { award(.bottledIt) }

        // Rivalry (accounts and claimed guests only)
        if let nemesis = nemesisBefore, game.contains(nemesis) {
            let theirs = game.totals[nemesis] ?? .max
            if result.finalScore < theirs { award(.nemesisTamed) }
            if (record.aheadStreak[nemesis] ?? 0) >= 3 { award(.exorcism) }
        }
        if record.sharedGames.contains(where: { !$0.key.isGuest && $0.value >= 10 }) { award(.grudgeMatch) }

        // Social
        if record.accountOpponents.count >= 10 { award(.playsWellWithOthers) }
        if game.playerCount >= 8 { award(.fullHouse) }
        if record.tauntsCounted >= 50 { award(.trashTalker) }

        return awards
    }

    /// The landed-knock streak going into a game (knocks are appended in replay order).
    private static func preGameLandedStreak(_ record: PlayerRecord, game: GameID) -> Int {
        let before = record.knockEvents.prefix { $0.gameID != game }
        return before.reversed().prefix { $0.outcome == .landed }.count
    }

    /// Bad Influence: a person who played with someone while that someone was a guest gets the
    /// badge when the guest, having claimed their history, finishes a game on their own account
    /// with at least one other person in it.
    static func badInfluence(in game: StatsGame, records: [PlayerRef: PlayerRecord]) -> [(PlayerRef, BadgeAward)] {
        var awards: [(PlayerRef, BadgeAward)] = []
        for participant in game.participants where !participant.seatedAs.isGuest {
            guard let claimed = records[participant.ref], !claimed.guestEraCompanions.isEmpty else { continue }
            for influencer in claimed.guestEraCompanions.sorted(by: { $0.seatID < $1.seatID }) where !influencer.isGuest {
                let someoneElse = game.refs.contains { $0 != influencer && $0 != participant.ref }
                guard someoneElse, records[influencer] != nil else { continue }
                awards.append((influencer, BadgeAward(
                    badge: .badInfluence, gameID: game.id, tableWord: game.tableWord, date: game.finishedAt, gameIndex: game.index
                )))
            }
        }
        return awards
    }

    /// #1 by rating among the person's people, with at least 5 ranked people (them included).
    static func isTopDog(_ me: PlayerRef, records: [PlayerRef: PlayerRecord]) -> Bool {
        guard let record = records[me], record.isRanked else { return false }
        let ranked = ([me] + record.sharedGames.keys.filter { !$0.isGuest }).compactMap { records[$0] }.filter(\.isRanked)
        guard ranked.count >= 5 else { return false }
        return ranked.allSatisfy { $0.ref == me || $0.rating < record.rating }
    }

    static func isTop100(_ me: PlayerRef, records: [PlayerRef: PlayerRecord]) -> Bool {
        guard let record = records[me], record.isRanked, !me.isGuest else { return false }
        let ranked = records.values.filter { $0.isRanked && !$0.isGuest }
        guard ranked.count >= top100MinimumBoard else { return false }
        return ranked.count { $0.rating > record.rating } < 100
    }

    /// Progress toward each unearned counting badge, closest first (Next up shows 3).
    static func progress(_ record: PlayerRecord) -> [BadgeProgress] {
        let bestLandedInGame = record.results.map(\.landed).max() ?? 0
        let grudge = record.sharedGames.filter { !$0.key.isGuest }.values.max() ?? 0
        let values: [(BadgeID, Int)] = [
            (.outOfTheGate, record.gamesPlayed), (.firstBlood, record.wins), (.onTheBoard, record.gamesPlayed),
            (.regular, record.gamesPlayed), (.touchGrass, record.gamesPlayed),
            (.hatTrick, bestLandedInGame), (.steadyHand, record.currentLandedStreak),
            (.threePeat, record.currentWinStreak), (.untouchable, record.currentWinStreak),
            (.grudgeMatch, grudge), (.playsWellWithOthers, record.accountOpponents.count),
            (.trashTalker, record.tauntsCounted),
        ]
        let order = Dictionary(uniqueKeysWithValues: BadgeID.allCases.enumerated().map { ($1, $0) })
        return values
            .filter { record.badges[$0.0] == nil }
            .compactMap { badge, value in badge.definition.target.map { BadgeProgress(badge: badge, value: value, target: $0) } }
            .sorted { lhs, rhs in
                if lhs.fraction != rhs.fraction { return lhs.fraction > rhs.fraction }
                if lhs.remaining != rhs.remaining { return lhs.remaining < rhs.remaining }
                return (order[lhs.badge] ?? 0) < (order[rhs.badge] ?? 0)
            }
    }
}
