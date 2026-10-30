import Foundation

/// Everything game end says about a finished game (design §10), derived from its rounds. Pure, so
/// the winner line ("by how they won") and the highlights are tested against the sample game.
nonisolated struct GameEndSummary: Sendable {
    /// A player's knock record: "✓2 =1 ✗1".
    struct KnockRecord: Hashable, Sendable {
        var landed = 0
        var tied = 0
        var failed = 0

        var isEmpty: Bool { landed + tied + failed == 0 }

        /// "✓2 =1 ✗1", leaving out zeros.
        var text: String {
            [("✓", landed), ("=", tied), ("✗", failed)]
                .filter { $0.1 > 0 }
                .map { "\($0.0)\($0.1)" }
                .joined(separator: " ")
        }

        var accessibilityText: String {
            [("landed", landed), ("tied", tied), ("failed", failed)]
                .filter { $0.1 > 0 }
                .map { "\($0.1) \($0.0)" }
                .joined(separator: ", ")
        }
    }

    enum Highlight: Hashable, Sendable {
        case bestHand(seat: SeatID, hand: Int, round: Int)
        case knocks(landed: Int, tied: Int, failed: Int)
        case comeback(seat: SeatID, worst: Int, afterRound: Int, final: Int)
        case decided(round: Int, seat: SeatID)
    }

    let winners: [SeatID]
    /// W-01 with the winner's name ("Noah and Ana" for a shared win).
    let headline: VoicePick?
    /// How they won (W-02/W-03/W-04/W-06), if anything special.
    let winnerLine: VoicePick?
    /// W-10 / W-11 for last place.
    let lastPlaceLine: VoicePick?
    /// W-07 for a runner-up who lost by one point.
    let lostByOne: SeatID?
    /// W-08 for someone who led into the final round and lost.
    let bottledLine: VoicePick?
    let knockRecords: [SeatID: KnockRecord]
    let highlights: [Highlight]

    /// A comeback means the winner was this far down after some round (W-02).
    static let comebackPosition = 3

    init(_ state: GameState) {
        let timeline = GameTimeline(state)
        let n = timeline.roundCount
        let standings = state.standings
        let winners = standings.filter(\.isLeader).map(\.id)
        self.winners = winners
        let name = { (seat: SeatID) in state.name(of: seat) }

        // Knock records
        var records: [SeatID: KnockRecord] = [:]
        for record in state.rounds {
            guard let outcome = record.outcome else { continue }
            switch outcome {
            case .landed: records[record.knocker, default: KnockRecord()].landed += 1
            case .tied: records[record.knocker, default: KnockRecord()].tied += 1
            case .failed: records[record.knocker, default: KnockRecord()].failed += 1
            }
        }
        knockRecords = records

        // Winner lines
        if winners.isEmpty || n == 0 {
            headline = nil
            winnerLine = nil
        } else {
            let names = ListFormatter.localizedString(byJoining: winners.map(name))
            headline = VoicePick(["W-01"], key: "winner", ["name": names])
            if winners.count > 1 {
                winnerLine = VoicePick(["W-06"], key: "winnerLine")
            } else if let winner = winners.first {
                winnerLine = Self.howTheyWon(winner, state: state, timeline: timeline)
            } else {
                winnerLine = nil
            }
        }

        // Last place and lost by one
        if let last = standings.last, standings.count >= 2, !last.isLeader {
            let id = last.total == 99 ? "W-11" : "W-10"
            lastPlaceLine = VoicePick([id], key: "lastPlace", ["name": last.seat.displayName, "score": last.total])
        } else {
            lastPlaceLine = nil
        }
        if winners.count == 1, let best = standings.first, let second = standings.dropFirst().first,
           second.total - best.total == 1 {
            lostByOne = second.id
        } else {
            lostByOne = nil
        }

        // Bottled it: led into the final round and didn't win.
        if n >= 2 {
            let ledIntoFinal = timeline.leaders(afterRound: n - 1).subtracting(winners)
            let roundsLed = { (seat: SeatID) in (1...n).filter { timeline.leaders(afterRound: $0).contains(seat) }.count }
            if let bottler = standings.first(where: { ledIntoFinal.contains($0.id) }) {
                bottledLine = VoicePick(["W-08"], key: "bottled", [
                    "name": bottler.seat.displayName, "n": roundsLed(bottler.id), "pos": bottler.rank.ordinal,
                ])
            } else {
                bottledLine = nil
            }
        } else {
            bottledLine = nil
        }

        highlights = Self.highlights(state: state, timeline: timeline, winners: winners, records: records)
    }

    private static func howTheyWon(_ winner: SeatID, state: GameState, timeline: GameTimeline) -> VoicePick? {
        let n = timeline.roundCount
        // Comeback: the worst position after any earlier round (the latest such round).
        if n >= 2 {
            var worst: (position: Int, round: Int)?
            for round in 1..<n {
                guard let position = timeline.position(of: winner, afterRound: round) else { continue }
                if position >= (worst?.position ?? 0) { worst = (position, round) }
            }
            if let worst, worst.position >= comebackPosition {
                let ordinal = Rank(position: worst.position, isShared: false).ordinal
                return VoicePick(["W-02"], key: "winnerLine", ["pos": ordinal, "r": worst.round])
            }
        }
        // Stole it on the last knock: not leading before the last round, then landed it.
        if n >= 2, let last = state.lastRound, last.knocker == winner, last.outcome == .landed,
           !timeline.leaders(afterRound: n - 1).contains(winner) {
            return VoicePick(["W-03"], key: "winnerLine")
        }
        // Wire to wire: led (or shared the lead) after every round.
        if n >= 2, (1...n).allSatisfy({ timeline.leaders(afterRound: $0).contains(winner) }) {
            return VoicePick(["W-04"], key: "winnerLine")
        }
        return nil
    }

    private static func highlights(state: GameState, timeline: GameTimeline, winners: [SeatID], records: [SeatID: KnockRecord]) -> [Highlight] {
        var result: [Highlight] = []
        let n = timeline.roundCount
        guard n > 0 else { return result }

        // Best hand: the lowest hand of the game (earliest round, then seat order).
        var best: (seat: SeatID, hand: Int, round: Int)?
        for record in state.rounds {
            for seat in state.seats.map(\.id) {
                guard let hand = record.round.hands[seat] else { continue }
                if best == nil || hand < (best?.hand ?? .max) { best = (seat, hand, record.number) }
            }
        }
        if let best { result.append(.bestHand(seat: best.seat, hand: best.hand, round: best.round)) }

        let totals = records.values.reduce(into: KnockRecord()) {
            $0.landed += $1.landed
            $0.tied += $1.tied
            $0.failed += $1.failed
        }
        result.append(.knocks(landed: totals.landed, tied: totals.tied, failed: totals.failed))

        // Biggest comeback: the largest climb from a worst position to the final one.
        if n >= 2 {
            var bestClimb: (seat: SeatID, worst: Int, round: Int, final: Int)?
            for standing in state.standings {
                var worst: (position: Int, round: Int)?
                for round in 1..<n {
                    guard let position = timeline.position(of: standing.id, afterRound: round) else { continue }
                    if position >= (worst?.position ?? 0) { worst = (position, round) }
                }
                guard let worst else { continue }
                let climb = worst.position - standing.rank.position
                if climb >= 2, climb > (bestClimb.map { $0.worst - $0.final } ?? 0) {
                    bestClimb = (standing.id, worst.position, worst.round, standing.rank.position)
                }
            }
            if let bestClimb {
                result.append(.comeback(seat: bestClimb.seat, worst: bestClimb.worst, afterRound: bestClimb.round, final: bestClimb.final))
            }
        }

        // The round that decided it: from then on, the winner led after every round.
        if winners.count == 1, let winner = winners.first {
            var decided = n
            while decided > 1, timeline.leaders(afterRound: decided - 1).contains(winner) {
                decided -= 1
            }
            result.append(.decided(round: decided, seat: winner))
        }
        return result
    }

    /// The literal line for a highlight.
    static func text(_ highlight: Highlight, name: (SeatID) -> String) -> String {
        switch highlight {
        case let .bestHand(seat, hand, round):
            TableText.text("label.highlight.bestHand", ["name": name(seat), "hand": hand, "r": round])
        case let .knocks(landed, tied, failed):
            TableText.text("label.highlight.knocks", ["landed": landed, "tied": tied, "failed": failed])
        case let .comeback(seat, worst, round, final):
            TableText.text("label.highlight.comeback", [
                "name": name(seat), "pos": Rank(position: worst, isShared: false).ordinal, "r": round,
                "final": Rank(position: final, isShared: false).ordinal,
            ])
        case let .decided(round, seat):
            TableText.text("label.highlight.decided", ["r": round, "name": name(seat)])
        }
    }
}
