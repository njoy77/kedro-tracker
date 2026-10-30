import Foundation

/// A rivalry between you and one other person, from shared finished games: who finished ahead
/// (lower total) more often. Equal totals count for nobody.
nonisolated struct Rivalry: Hashable, Sendable, Identifiable {
    var opponent: PlayerRef
    var name: String
    var avatar: Avatar?
    var isGuest: Bool
    /// Shared games you finished ahead.
    var mine: Int
    /// Shared games they finished ahead.
    var theirs: Int
    var gamesTogether: Int

    var id: PlayerRef { opponent }
    var theyLead: Bool { theirs > mine }
    var youLead: Bool { mine > theirs }
}

/// A row in "Since you last looked" (design §12.1).
nonisolated enum DigestItem: Hashable, Sendable, Identifiable {
    /// Your latest finished game since you last looked.
    case lastGame(gameID: GameID, word: String, rank: Rank, isWin: Bool)
    /// You took the lead in a rivalry (J-08).
    case rivalryFlipped(Rivalry)
    /// Someone sent you a receipt (N-08).
    case receipt(id: UUID, gameID: GameID, fromName: String, fromAvatar: Avatar?, fromIsGuest: Bool, word: String)

    var id: String {
        switch self {
        case .lastGame(let game, _, _, _): "game:\(game)"
        case .rivalryFlipped(let rivalry): "rivalry:\(rivalry.opponent)"
        case .receipt(let id, _, _, _, _, _): "receipt:\(id)"
        }
    }
}

/// One line of stakes (design §12.1 "Tonight's stakes", §5.6 lobby, §5.3 Table card).
nonisolated enum StakesLine: Hashable, Sendable {
    /// Your 5th game: finish it and you're on the board (J-01).
    case fifthGame
    /// Someone leads you; tonight's a good night to fix that (J-05).
    case rivalLeads(Rivalry)
    /// Nothing on the line (J-10).
    case nothing

    /// The copy deck line in a voice.
    func text(_ voice: Voice) -> String {
        switch self {
        case .fifthGame: voice.line("J-01")
        case .rivalLeads(let rivalry): voice.line("J-05", ["name": rivalry.name, "a": rivalry.theirs, "b": rivalry.mine])
        case .nothing: voice.line("J-10")
        }
    }
}

/// Derived, never stored (design §12): Play's digest and stakes, computed from finished games.
///
/// Ratings, board movement and badges come from Core/Stats (stats agent); until Play can read
/// them, the rating-based lines (J-06 "pass the player above", J-07 "passed you", the rating
/// delta in J-09, closest badge) are left out rather than estimated differently from the board.
nonisolated enum PlayInsights {
    /// Finished, non-abandoned games you were seated at.
    static func gamesPlayed(by me: PlayerRef, in games: [GameState]) -> Int {
        games.filter { $0.status == .finished && $0.seat(for: me) != nil }.count
    }

    /// Every rivalry from shared finished games, optionally only games finished before `date`.
    static func rivalries(for me: PlayerRef, in games: [GameState], before date: Date? = nil) -> [PlayerRef: Rivalry] {
        var result: [PlayerRef: Rivalry] = [:]
        for game in games where game.status == .finished {
            if let date, let finished = game.finishedAt, finished >= date { continue }
            guard let mySeat = game.seat(for: me), let myTotal = game.standing(for: mySeat.id)?.total else { continue }
            for standing in game.standings where standing.seat.player != me {
                let seat = standing.seat
                var rivalry = result[seat.player] ?? Rivalry(
                    opponent: seat.player, name: seat.displayName, avatar: seat.avatar,
                    isGuest: seat.isGuest, mine: 0, theirs: 0, gamesTogether: 0
                )
                rivalry.name = seat.displayName
                rivalry.avatar = seat.avatar ?? rivalry.avatar
                rivalry.gamesTogether += 1
                if myTotal < standing.total { rivalry.mine += 1 }
                if standing.total < myTotal { rivalry.theirs += 1 }
                result[seat.player] = rivalry
            }
        }
        return result
    }

    /// "Since you last looked": your latest game, rivalries you took the lead in, receipts.
    /// With no `since`, only the latest game shows.
    static func digest(for me: PlayerRef, in games: [GameState], since: Date?) -> [DigestItem] {
        var items: [DigestItem] = []
        let mine = games
            .filter { $0.status == .finished && $0.seat(for: me) != nil }
            .sorted { ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast) }

        if let latest = mine.first, since.map({ (latest.finishedAt ?? .distantPast) > $0 }) ?? true,
           let seat = latest.seat(for: me), let standing = latest.standing(for: seat.id) {
            items.append(.lastGame(gameID: latest.gameID, word: latest.config.tableWord, rank: standing.rank, isWin: standing.isLeader))
        }

        guard let since else { return items }

        let before = rivalries(for: me, in: games, before: since)
        let now = rivalries(for: me, in: games)
        let flipped = now.values
            .filter { $0.youLead && !(before[$0.opponent]?.youLead ?? false) && (before[$0.opponent]?.gamesTogether ?? 0) > 0 }
            .sorted { $0.gamesTogether > $1.gamesTogether }
        items += flipped.prefix(2).map(DigestItem.rivalryFlipped)

        for game in mine {
            guard let mySeat = game.seat(for: me) else { continue }
            for receipt in game.receipts where receipt.to == mySeat.id && receipt.at > since {
                let from = game.seat(receipt.from)
                items.append(.receipt(
                    id: receipt.opId, gameID: game.gameID, fromName: from?.displayName ?? "Someone",
                    fromAvatar: from?.avatar, fromIsGuest: from?.isGuest ?? false, word: game.config.tableWord
                ))
            }
        }
        return items
    }

    /// Stakes, most important first (design §12.1: rank threshold > pass the player above >
    /// level a rivalry > closest badge). `opponents` narrows rivalries to the people at a table.
    static func stakes(for me: PlayerRef, in games: [GameState], opponents: Set<PlayerRef>? = nil, limit: Int = 2) -> [StakesLine] {
        var lines: [StakesLine] = []
        if gamesPlayed(by: me, in: games) == 4 { lines.append(.fifthGame) }
        // TODO(stats): J-06 "a win tonight would likely put you past {name}" from ratings.
        let rivals = rivalries(for: me, in: games).values
            .filter { $0.theyLead && (opponents?.contains($0.opponent) ?? true) }
            .sorted { ($0.theirs - $0.mine, -$0.gamesTogether, $0.name) < ($1.theirs - $1.mine, -$1.gamesTogether, $1.name) }
        if let rival = rivals.first { lines.append(.rivalLeads(rival)) }
        // TODO(stats): closest badge.
        return lines.isEmpty ? [.nothing] : Array(lines.prefix(limit))
    }
}
