import Foundation

/// Tonight's stakes: one line for the Table card and lobby (design §12.1, §12.5). Priority: rank
/// threshold > pass the player above > level a rivalry > closest badge. Facts, or estimates that
/// say so (J-06 "based on your ratings").
nonisolated struct TonightStakes: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// Game 5 puts you on the board (J-01).
        case rankThreshold
        /// A win would likely pass the person above you (J-06, an estimate).
        case passPlayer(PlayerRef)
        /// Someone at the table leads your rivalry (J-05).
        case levelRivalry(PlayerRef)
        /// The closest badge (literal progress line).
        case closestBadge(BadgeID)
        /// Nothing on the line (J-10).
        case nothing
    }

    var kind: Kind
    /// Rendered in the voice passed in.
    var text: String
    var isEstimate: Bool
    /// The 5-step meter value for unranked players (nil once ranked).
    var meter: Int?
}

/// One line in "Since you last looked" (design §12.1). Loss-framed lines ("you were passed")
/// appear only here, never as pushes (§12.5 guardrails).
nonisolated struct SinceYouLastLookedItem: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        /// Your last result and rating change (J-09), or your meter while unranked (L-01).
        case lastGame(GameID)
        /// Someone passed you on your Played With board (J-07).
        case passed(PlayerRef)
        /// You now lead a rivalry (J-08).
        case rivalryFlipped(PlayerRef)
        /// Someone took a held title off you (TI-19).
        case titleLost(TitleID, by: PlayerRef)
        /// Someone you play with made the Hall of Shame at a table you weren't at (HS-09).
        case hallOfShame(ShameEntry)
        /// Your closest badge.
        case closestBadge(BadgeProgress)
    }

    var kind: Kind
    var text: String

    var id: String {
        switch kind {
        case .lastGame(let game): "game|\(game.uuidString)"
        case .passed(let ref): "passed|\(ref.seatID.rawValue)"
        case .rivalryFlipped(let ref): "rivalry|\(ref.seatID.rawValue)"
        case let .titleLost(title, by): "title|\(title.rawValue)|\(by.seatID.rawValue)"
        case .hallOfShame(let entry): "shame|\(entry.id)"
        case .closestBadge(let progress): "badge|\(progress.badge.rawValue)"
        }
    }
}

/// What the Lobby agent's Play tab reads (design §12.1). `StatsModel` implements it.
protocol StakesProvider: AnyObject {
    func tonightsStakes(for me: PlayerRef, table: [PlayerRef], voice: Voice) -> TonightStakes
    func sinceYouLastLooked(for me: PlayerRef, since: Date?, voice: Voice) -> [SinceYouLastLookedItem]
}

extension StatsSnapshot {
    func tonightsStakes(for me: PlayerRef, table: [PlayerRef], voice: Voice) -> TonightStakes {
        let me = options.canonical(me)
        let table = table.map(options.canonical).filter { $0 != me && !options.excluded.contains($0) }
        let record = record(me)
        let games = record?.gamesPlayed ?? 0
        let meter = games < Ratings.rankedAfterGames ? games : nil

        if games == Ratings.rankedAfterGames - 1 {
            return TonightStakes(kind: .rankThreshold, text: voice.line("J-01"), isEstimate: false, meter: meter)
        }

        if let record, record.isRanked {
            let board = leaderboard(scope: .playedWith, sort: .rating, viewer: me)
            if let index = board.viewerIndex,
               let above = board.ranked[..<index].last(where: { $0.value > board.ranked[index].value }) {
                // Estimate: I win tonight and everyone else ties behind me.
                let seats = [me] + table
                let totals = Dictionary(uniqueKeysWithValues: seats.map { ($0, $0 == me ? 0 : 1) })
                let ratings = Dictionary(uniqueKeysWithValues: seats.map { ($0, records[$0]?.rating ?? Ratings.startingRating) })
                let played = Dictionary(uniqueKeysWithValues: seats.map { ($0, records[$0]?.gamesPlayed ?? 0) })
                let deltas = Ratings.deltas(totals: totals, ratings: ratings, gamesBefore: played)
                let mine = record.rating + (deltas[me] ?? 0)
                let theirs = (records[above.ref]?.rating ?? above.value) + (deltas[above.ref] ?? 0)
                if table.count >= 1, mine > theirs {
                    return TonightStakes(
                        kind: .passPlayer(above.ref),
                        text: voice.line("J-06", ["name": above.identity.name]),
                        isEstimate: true, meter: nil
                    )
                }
            }
        }

        let rivals = table.map { ($0, headToHead($0, me)) }.filter { $0.1.aAhead > $0.1.bAhead }
        if let rival = rivals.min(by: { lhs, rhs in
            lhs.1.gap != rhs.1.gap ? lhs.1.gap < rhs.1.gap : lhs.1.gamesTogether > rhs.1.gamesTogether
        }) {
            return TonightStakes(
                kind: .levelRivalry(rival.0),
                text: voice.line("J-05", ["name": name(of: rival.0), "a": rival.1.aAhead, "b": rival.1.bAhead]),
                isEstimate: false, meter: meter
            )
        }

        if let record, let next = BadgeEvaluator.progress(record).first(where: { $0.value > 0 }) {
            return TonightStakes(kind: .closestBadge(next.badge), text: StatsLiteral.nextUp(next), isEstimate: false, meter: meter)
        }
        return TonightStakes(kind: .nothing, text: voice.line("J-10"), isEstimate: false, meter: meter)
    }

    /// Changes since a moment (`AppPreferences.lastLookedAt`), newest-relevant first.
    func sinceYouLastLooked(for me: PlayerRef, since: Date?, voice: Voice, now: Date = .now) -> [SinceYouLastLookedItem] {
        let me = options.canonical(me)
        guard let record = record(me) else { return [] }
        var items: [SinceYouLastLookedItem] = []

        if let last = record.results.last, since.map({ last.date > $0 }) ?? true {
            let text: String
            if record.isRanked {
                let result = last.isWinner ? (last.isSharedWin ? "Shared the win" : "Won") : last.rank.ordinal
                text = voice.line("J-09", ["result": result, "word": last.tableWord, "delta": ScoreFormat.signed(last.ratingDelta)])
            } else {
                text = voice.line("L-01", ["n": record.gamesPlayed, "left": Ratings.rankedAfterGames - record.gamesPlayed])
            }
            items.append(.init(kind: .lastGame(last.gameID), text: text))
        }

        if let since {
            let earlier = asOf(since)
            // Passed on the board.
            let boardNow = leaderboard(scope: .playedWith, sort: .rating, viewer: me)
            let boardThen = earlier.leaderboard(scope: .playedWith, sort: .rating, viewer: me)
            if let myNow = boardNow.viewerRow?.rank, let myThen = boardThen.viewerRow?.rank {
                for row in boardNow.ranked where !row.isViewer {
                    guard let theirNow = row.rank, theirNow < myNow,
                          let theirThen = boardThen.ranked.first(where: { $0.ref == row.ref })?.rank, theirThen > myThen
                    else { continue }
                    items.append(.init(kind: .passed(row.ref), text: voice.line("J-07", ["name": row.identity.name])))
                }
            }
            // Rivalries that flipped your way.
            for opponent in people(of: me).sorted(by: { $0.seatID < $1.seatID }) {
                let current = headToHead(me, opponent), previous = earlier.headToHead(me, opponent)
                guard current.aAhead > current.bAhead, previous.aAhead <= previous.bAhead, previous.gamesTogether > 0 else { continue }
                items.append(.init(
                    kind: .rivalryFlipped(opponent),
                    text: voice.line("J-08", ["name": name(of: opponent), "a": current.aAhead, "b": current.bAhead])
                ))
            }
            // Held titles taken off you.
            for (title, holder) in titlesLost(by: me, since: earlier, now: now) {
                items.append(.init(
                    kind: .titleLost(title, by: holder),
                    text: voice.line("TI-19", ["name": name(of: holder), "title": voice.line(title.copyID)])
                ))
            }
            // Hall of Shame inductions at tables you weren't at.
            let fresh = hallOfShame(scope: .yourPeople, viewer: me).flatMap(\.entries).filter { entry in
                entry.date > since && entry.player != me && !(game(entry.gameID)?.contains(me) ?? false)
            }
            for entry in fresh {
                items.append(.init(
                    kind: .hallOfShame(entry),
                    text: voice.line("HS-09", ["name": entry.identity.name, "category": entry.category.name])
                ))
            }
        }

        if let next = BadgeEvaluator.progress(record).first(where: { $0.value > 0 }) {
            items.append(.init(kind: .closestBadge(next), text: StatsLiteral.nextUp(next)))
        }
        return items
    }
}

/// Literal (level-independent) stats lines.
nonisolated enum StatsLiteral {
    /// "Next up: Three-Peat, 1 of 3."
    static func nextUp(_ progress: BadgeProgress) -> String {
        "Next up: \(progress.badge.definition.name), \(progress.label)."
    }

    /// "Needs 15 knocks for this one." (the knock-success twin of L-05).
    static let needsKnocks = CopyEntry("L-05k", "Below the knock-success minimum", clean: "Needs {n} knocks for this one.")
}
