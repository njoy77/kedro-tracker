import Foundation

/// Knock outcomes as a ✓ = ✗ triple.
nonisolated struct KnockTally: Hashable, Sendable {
    var landed = 0
    var tied = 0
    var failed = 0

    var total: Int { landed + tied + failed }

    mutating func add(_ outcome: KnockOutcome) {
        switch outcome {
        case .landed: landed += 1
        case .tied: tied += 1
        case .failed: failed += 1
        case .noPenalty: break // inherent knocks aren't knocks
        }
    }

    /// "✓9 =2 ✗4" (literal glyphs, design §3.6).
    var label: String { "✓\(landed) =\(tied) ✗\(failed)" }

    var accessibilityLabel: String { "\(landed) landed, \(tied) tied, \(failed) failed" }
}

/// Two people's shared record (PRD §5.2, design §12.3).
nonisolated struct HeadToHead: Hashable, Sendable {
    var a: PlayerRef
    var b: PlayerRef
    var gamesTogether: Int
    /// Games where a finished ahead of b, and the reverse. Equal totals count for neither.
    var aAhead: Int
    var bAhead: Int
    /// Wins (shared wins count) in their shared games.
    var aWins: Int
    var bWins: Int
    /// Each one's knocks in games they shared.
    var aKnocks: KnockTally
    var bKnocks: KnockTally
    var aAverageFinal: Double?
    var bAverageFinal: Double?
    var lastMeeting: Meeting?

    struct Meeting: Hashable, Sendable {
        var gameID: GameID
        var tableWord: String
        var date: Date
        var aScore: Int
        var bScore: Int
    }

    /// Who leads the rivalry (nil when level).
    var leader: PlayerRef? {
        if aAhead > bAhead { return a }
        if bAhead > aAhead { return b }
        return nil
    }

    var gap: Int { abs(aAhead - bAhead) }
}

extension StatsSnapshot {
    func headToHead(_ first: PlayerRef, _ second: PlayerRef) -> HeadToHead {
        let a = options.canonical(first), b = options.canonical(second)
        var h2h = HeadToHead(
            a: a, b: b, gamesTogether: 0, aAhead: 0, bAhead: 0, aWins: 0, bWins: 0,
            aKnocks: KnockTally(), bKnocks: KnockTally(), aAverageFinal: nil, bAverageFinal: nil, lastMeeting: nil
        )
        guard a != b else { return h2h }
        var aSum = 0, bSum = 0
        for game in games where game.contains(a) && game.contains(b) {
            let aTotal = game.totals[a] ?? 0, bTotal = game.totals[b] ?? 0
            h2h.gamesTogether += 1
            aSum += aTotal
            bSum += bTotal
            if aTotal < bTotal { h2h.aAhead += 1 }
            if bTotal < aTotal { h2h.bAhead += 1 }
            if game.winners.contains(a) { h2h.aWins += 1 }
            if game.winners.contains(b) { h2h.bWins += 1 }
            for round in game.rounds {
                guard let outcome = round.outcome else { continue }
                if round.regularKnocker == a { h2h.aKnocks.add(outcome) }
                if round.regularKnocker == b { h2h.bKnocks.add(outcome) }
            }
            h2h.lastMeeting = .init(gameID: game.id, tableWord: game.tableWord, date: game.finishedAt, aScore: aTotal, bScore: bTotal)
        }
        if h2h.gamesTogether > 0 {
            h2h.aAverageFinal = Double(aSum) / Double(h2h.gamesTogether)
            h2h.bAverageFinal = Double(bSum) / Double(h2h.gamesTogether)
        }
        return h2h
    }

    /// The people someone has played with most, most games first (profile "Rivals").
    func rivals(of ref: PlayerRef, limit: Int = 3) -> [PlayerRef] {
        guard let record = record(ref) else { return [] }
        return record.sharedGames
            .filter { !options.excluded.contains($0.key) }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.seatID < rhs.key.seatID
            }
            .prefix(limit)
            .map(\.key)
    }
}
