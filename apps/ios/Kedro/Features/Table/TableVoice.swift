import Foundation

/// A chosen voice line: candidate copy IDs (one is picked by the stable seed), the seed's key, and
/// the arguments. Selection is pure and tested; rendering happens in the view with the right voice.
nonisolated struct VoicePick: Sendable {
    var ids: [String]
    var key: String
    var args: VoiceArgs

    init(_ ids: [String], key: String, _ args: VoiceArgs = [:]) {
        self.ids = ids
        self.key = key
        self.args = args
    }

    init(_ moment: VoiceMoment, _ args: VoiceArgs = [:]) {
        self.init(moment.variantIDs, key: moment.rawValue, args)
    }

    func render(_ voice: Voice, gameID: GameID, round: Int) -> String {
        voice.line(oneOf: ids, args, seed: VoiceSeed(gameID: gameID, round: round, key: key))
    }
}

/// Standings after each round, for banter and game-end lines.
nonisolated struct GameTimeline: Sendable {
    /// `totals[k]` and `ranks[k]` are after round k+1.
    let totals: [[SeatID: Int]]
    let ranks: [[SeatID: Rank]]
    let seats: [SeatID]

    init(_ state: GameState) {
        seats = state.seats.map(\.id)
        var running: [SeatID: Int] = Dictionary(uniqueKeysWithValues: seats.map { ($0, 0) })
        var totals: [[SeatID: Int]] = []
        var ranks: [[SeatID: Rank]] = []
        for record in state.rounds {
            for (seat, score) in record.scores { running[seat, default: 0] += score }
            totals.append(running)
            ranks.append(Scoring.ranks(running))
        }
        self.totals = totals
        self.ranks = ranks
    }

    var roundCount: Int { totals.count }

    /// Leaders after round `number` (1-based).
    func leaders(afterRound number: Int) -> Set<SeatID> {
        guard number >= 1, number <= totals.count else { return [] }
        return Scoring.winners(totals[number - 1])
    }

    func position(of seat: SeatID, afterRound number: Int) -> Int? {
        guard number >= 1, number <= ranks.count else { return nil }
        return ranks[number - 1][seat]?.position
    }

    /// Seats in last place (the worst position) after a round.
    func last(afterRound number: Int) -> Set<SeatID> {
        guard number >= 1, number <= totals.count, let worst = totals[number - 1].values.max() else { return [] }
        return Set(totals[number - 1].filter { $0.value == worst }.keys)
    }
}

/// Picks the Table's voice lines (design §8.2): the roast on the last-round card and the banter
/// line under the standings.
nonisolated enum TableVoice {
    /// Hands this big get the K-20 line ("Bad sticks have consequences").
    static let hugeHand = 40
    /// A failed knock by this much is a circus (K-08).
    static let bigFailMargin = 8
    /// A learner's own hand this big gets the peeks lesson (K-31).
    static let learnerBigHand = 20
    /// "Cooked" estimate (B-03): further back than this many points per remaining round. The line
    /// itself states the basis ("21 back with 3 to play").
    static let cookedPointsPerRound = 6
    static let bigLead = 15
    static let closeTable = 10
    /// Dealer lines appear at most once every this many rounds (design §6.4).
    static let dealerLineEvery = 3

    // MARK: Roast

    /// The roast under a round's fact and verdict. `viewer` is this phone's seat: a learner gets a
    /// teaching line for their own bad outcome (K-30s), and the player who beat the knocker gets K-10.
    static func roast(for record: RoundRecord, in state: GameState, viewer: SeatID?, viewerIsLearner: Bool) -> VoicePick? {
        let round = record.round
        guard let hand = round.knockerHand, let outcome = record.outcome else { return nil }
        let knockerName = state.name(of: round.knocker)
        let lowSeat = round.lowestOtherSeat
        let low = round.lowestOtherHand
        var args: VoiceArgs = ["knocker": knockerName, "hand": hand]
        if let lowSeat, let low {
            args["name"] = state.name(of: lowSeat)
            args["low"] = low
        }

        if let viewer, viewerIsLearner {
            if viewer == round.knocker, outcome == .failed { return VoicePick(.learnerFailedKnock, args) }
            if viewer == round.knocker, outcome == .tied { return VoicePick(.learnerTiedKnock, args) }
            if let own = round.hands[viewer], own >= learnerBigHand {
                return VoicePick(.learnerBigHand, ["hand": own])
            }
        }

        // A red King deciding the round beats everything (design §6.1).
        if let lowest = round.hands.values.min(), lowest <= -2 { return VoicePick(.bothRedKings, args) }
        if record.redKingDecided { return VoicePick(.redKing, args) }

        if outcome == .failed, let viewer, viewer == lowSeat, viewer != round.knocker {
            return VoicePick(.beatTheKnocker, args)
        }

        switch outcome {
        case .failed:
            let margin = hand - (low ?? hand)
            if margin >= bigFailMargin { return VoicePick(.knockFailedBig, args) }
            if margin == 1 { return VoicePick(.knockFailedByOne, args) }
            return VoicePick(.knockFailed, args)
        case .landed, .tied:
            if let big = round.hands.filter({ $0.key != round.knocker }).max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
               big.value >= hugeHand {
                return VoicePick(.hugeHand, ["name": state.name(of: big.key), "hand": big.value])
            }
            if outcome == .tied { return VoicePick(.knockTied, args) }
            return hand <= 0 ? VoicePick(.knockLandedLow, args) : VoicePick(.knockLanded, args)
        }
    }

    // MARK: Banter

    /// The furthest-back player who needs more than `cookedPointsPerRound` a round to catch the
    /// leader with `remaining` rounds to play, given `totals` (the B-03 estimate).
    static func cookedSeat(totals: [SeatID: Int], remaining: Int, ordered: [Standing]) -> Standing? {
        guard remaining >= 1, let best = totals.values.min() else { return nil }
        return ordered
            .filter { (totals[$0.id] ?? 0) - best > cookedPointsPerRound * remaining }
            .max { (totals[$0.id] ?? 0, $1.seat.order) < (totals[$1.id] ?? 0, $0.seat.order) }
    }

    /// The banter line under the standings (B-xx, or an occasional dealer line D-02…D-05).
    /// Changes only when a round is saved, edited or undone (it's derived from the rounds).
    static func banter(for state: GameState) -> VoicePick? {
        let timeline = GameTimeline(state)
        let n = timeline.roundCount
        guard n >= 1, state.status == .active else { return nil }
        let now = timeline.totals[n - 1]
        let leaders = timeline.leaders(afterRound: n)
        let ordered = state.standings
        let remaining = state.progress.remainingRounds
        let name = { (seat: SeatID) in state.name(of: seat) }

        // B-07: the leader just failed a knock.
        if n >= 2, let last = state.lastRound, last.outcome == .failed,
           timeline.leaders(afterRound: n - 1).contains(last.knocker) {
            return VoicePick(["B-07"], key: "banter")
        }
        // B-03 the round someone first becomes cooked (mockup frame 6: "Sam's 21 back with 3 to
        // play"); while it stays true it drops down the list so the line keeps moving.
        if let cooked = cookedSeat(totals: now, remaining: remaining, ordered: ordered) {
            let wasCooked = n >= 2 && cookedSeat(totals: timeline.totals[n - 2], remaining: remaining + 1, ordered: ordered)?.id == cooked.id
            if !wasCooked {
                return VoicePick(["B-03"], key: "banter", ["name": cooked.seat.displayName, "gap": cooked.total - (now.values.min() ?? 0), "n": remaining])
            }
        }
        // B-05: a tie at the top.
        let leaderSeats = ordered.filter { leaders.contains($0.id) }
        if leaderSeats.count >= 2 {
            return VoicePick(["B-05"], key: "banter", ["a": leaderSeats[0].seat.displayName, "b": leaderSeats[1].seat.displayName, "score": leaderSeats[0].total])
        }
        // B-01: a new leader.
        if n >= 2, leaders.count == 1, let leader = leaders.first, !timeline.leaders(afterRound: n - 1).contains(leader) {
            return VoicePick(["B-01"], key: "banter", ["name": name(leader)])
        }
        // B-06: last round next.
        if remaining == 1 {
            return VoicePick(["B-06"], key: "banter")
        }
        // B-04: last two rounds ago, now 2nd.
        if n >= 3 {
            let wasLast = timeline.last(afterRound: n - 2)
            if let comeback = ordered.first(where: { wasLast.contains($0.id) && $0.rank.position == 2 && !$0.rank.isShared }) {
                return VoicePick(["B-04"], key: "banter", ["name": comeback.seat.displayName])
            }
        }
        // B-03: still cooked (estimate stated in the line).
        if let cooked = cookedSeat(totals: now, remaining: remaining, ordered: ordered), let best = now.values.min() {
            return VoicePick(["B-03"], key: "banter", ["name": cooked.seat.displayName, "gap": cooked.total - best, "n": remaining])
        }
        // B-09: the same player last three rounds running.
        if n >= 3 {
            let lasts = (n - 2...n).map { timeline.last(afterRound: $0) }
            if lasts.allSatisfy({ $0.count == 1 }), let seat = lasts[0].first, lasts.allSatisfy({ $0.first == seat }) {
                return VoicePick(["B-09"], key: "banter", ["name": name(seat)])
            }
        }
        // B-02: a big lead.
        if leaderSeats.count == 1, ordered.count >= 2, ordered[1].total - ordered[0].total >= bigLead {
            return VoicePick(["B-02"], key: "banter", ["name": ordered[0].seat.displayName, "gap": ordered[1].total - ordered[0].total])
        }
        // B-08: the whole table within 10.
        if n >= 2, ordered.count >= 3, let low = now.values.min(), let high = now.values.max(), high - low <= closeTable {
            return VoicePick(["B-08"], key: "banter")
        }
        // Dealer line, when nothing else is happening (never more than once every 3 rounds).
        if n % dealerLineEvery == 0, let dealer = state.currentDealer {
            if leaders.contains(dealer) { return VoicePick(["D-05"], key: "dealer", ["name": name(dealer)]) }
            if let last = state.lastRound, last.knocker == dealer, last.outcome == .failed {
                return VoicePick(["D-04"], key: "dealer", ["name": name(dealer)])
            }
            return VoicePick(.dealerLine, ["name": name(dealer)])
        }
        return nil
    }
}
