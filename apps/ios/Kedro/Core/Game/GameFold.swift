import Foundation

extension GameState {
    /// How long an abandoned game can be restored, and how long after finishing a racing abandon
    /// still wins (design §9.3, §11).
    nonisolated static let restoreWindowMs: Int64 = 15 * 60 * 1000

    /// Folds an operation log into the game's state.
    ///
    /// Deterministic: operations are de-duplicated by `opId` and applied in (HLC, deviceId, opId)
    /// order, so every phone that holds the same operations shows the same game, whatever order
    /// they arrived in. Conflict rules (design §11):
    /// - concurrent edits: the later HLC wins (it's applied last);
    /// - a round recorded twice: the earlier is kept, the other becomes a `RoundConflict`;
    /// - after `GameFinished`, state-changing operations are refused (`lateOperations`), and the
    ///   finisher's `finalRounds` are authoritative;
    /// - abandon beats everything except a restore within 15 minutes.
    ///
    /// - Parameter gameID: The game to fold. Defaults to the first operation's game; operations
    ///   for other games are ignored.
    nonisolated static func fold(_ operations: [GameOperation], gameID: GameID? = nil) -> GameState {
        guard let id = gameID ?? operations.first?.gameId else {
            return GameState(gameID: GameID())
        }
        var seen = Set<UUID>()
        let ordered = operations
            .filter { $0.gameId == id && seen.insert($0.opId).inserted }
            .sorted(by: GameOperation.foldOrder)
        var reducer = GameReducer(gameID: id)
        for operation in ordered {
            reducer.apply(operation)
        }
        return reducer.makeState()
    }
}

/// Applies operations one at a time. Internal to `GameState.fold`.
private nonisolated struct GameReducer {
    var state: GameState
    private var created = false
    private var statusBeforeAbandon: GameStatus = .lobby
    private var abandonedHLC: HLC?
    private var finishedHLC: HLC?
    private var liveKnocks: [Int: LiveKnock] = [:]
    private var reports: [Int: [SeatID: Op.HandReported]] = [:]
    private var reportOrder: [Int: [SeatID]] = [:]
    private var proposals: [Int: [KnockerProposal]] = [:]
    private var resolvedKnockers: [Int: SeatID] = [:]
    /// The most recent operation that changed each round (for late detection at finish).
    private var lastTouch: [Int: GameOperation] = [:]

    init(gameID: GameID) {
        state = GameState(gameID: gameID)
    }

    // MARK: Apply

    mutating func apply(_ op: GameOperation) {
        state.latestHLC = op.hlc
        let actor = resolveActor(op)

        switch state.status {
        case .abandoned:
            switch op.payload {
            case .gameRestored: break
            case .gameAbandoned: return
            default:
                if op.type.isStateChanging || op.type == .tauntSent { refuse(op, actor, .afterAbandon) }
                return
            }
        case .finished:
            switch op.payload {
            case .receiptSent, .reactionAdded, .tableSpeakerClaimed, .tauntRetracted:
                break
            case .gameFinished:
                return // a second phone also tapped Finish
            case .gameAbandoned:
                // Abandon beats finish only when the two raced (within the restore window).
                guard let finishedHLC, op.hlc.wallMs - finishedHLC.wallMs <= GameState.restoreWindowMs else {
                    refuse(op, actor, .afterFinish)
                    return
                }
            default:
                refuse(op, actor, .afterFinish)
                return
            }
        case .lobby, .active:
            break
        }

        switch op.payload {
        case .gameCreated(let p): applyGameCreated(p, op)
        case .gameStarted(let p): applyGameStarted(p, op)
        case .playerSeated(let p): applyPlayerSeated(p, op, actor)
        case .seatRemoved(let p): applySeatRemoved(p, op, actor)
        case .scorekeeperChanged(let p): applyScorekeeperChanged(p, op, actor)
        case .roundRecorded(let p): applyRoundRecorded(p.round, op, actor, recordedBy: actor.name)
        case .roundEdited(let p): applyRoundEdited(p.round, op, actor)
        case .roundUndone(let p): applyRoundUndone(p, op, actor)
        case .knockMarked(let p): applyKnockMarked(p, op, actor)
        case .knockerProposed(let p): applyKnockerProposed(p, op, actor)
        case .knockerResolved(let p): applyKnockerResolved(p, op, actor)
        case .handReported(let p): applyHandReported(p, op, actor)
        case .roundsChanged(let p): applyRoundsChanged(p, op, actor)
        case .dealerChanged(let p): applyDealerChanged(p, op, actor)
        case .tauntSent(let p): applyTauntSent(p, op)
        case .tauntRetracted(let p): applyTauntRetracted(p)
        case .reactionAdded(let p): applyReactionAdded(p, op)
        case .receiptSent(let p): applyReceiptSent(p, op)
        case .tableSpeakerClaimed(let p): state.tableSpeaker = p.deviceId
        case .gameFinished(let p): applyGameFinished(p, op, actor)
        case .gameAbandoned: applyGameAbandoned(op, actor)
        case .gameRestored: applyGameRestored(op, actor)
        }
    }

    // MARK: Setup and seats

    private mutating func applyGameCreated(_ p: Op.GameCreated, _ op: GameOperation) {
        guard !created else { return }
        created = true
        state.config = p.config
        state.hostSeat = p.host
        state.createdAt = op.hlc.date
    }

    private mutating func applyGameStarted(_ p: Op.GameStarted, _ op: GameOperation) {
        guard state.status == .lobby else { return }
        for (index, id) in p.seatOrder.enumerated() {
            if let seatIndex = state.seats.firstIndex(where: { $0.id == id }) {
                state.seats[seatIndex].order = index
            }
        }
        // Seats missing from `seatOrder` keep their relative order after the listed ones.
        let listed = Set(p.seatOrder)
        var next = p.seatOrder.count
        for seatIndex in state.seats.indices.sorted(by: { seatSort(state.seats[$0], state.seats[$1]) })
        where !listed.contains(state.seats[seatIndex].id) {
            state.seats[seatIndex].order = next
            next += 1
        }
        sortSeats()
        let firstDealer = state.seat(p.firstDealer) != nil ? p.firstDealer : state.seats.first?.id
        if let firstDealer {
            state.config.firstDealerSeat = firstDealer
            state.dealerAnchor = DealerAnchor(roundNumber: 1, seat: firstDealer)
        }
        state.status = .active
        state.startedAt = op.hlc.date
    }

    private mutating func applyPlayerSeated(_ p: Op.PlayerSeated, _ op: GameOperation, _ actor: GameActor) {
        let incoming = p.seat
        if let index = state.seats.firstIndex(where: { $0.id == incoming.id }) {
            let previous = state.seats[index]
            var updated = incoming
            if !state.rounds.isEmpty || state.status != .lobby {
                updated.order = previous.order // seats are fixed once the game starts
            }
            state.seats[index] = updated
            sortSeats()
            if state.status == .active, let device = incoming.deviceID, device != previous.deviceID {
                log(.seatLinked(seat: incoming.id), op, actor)
            }
            return
        }
        guard state.rounds.isEmpty else { return refuse(op, actor, .seatsLocked) }
        guard state.seats.count < GameConfig.seatRange.upperBound else { return refuse(op, actor, .tableFull) }
        state.seats.append(incoming)
        sortSeats()
    }

    private mutating func applySeatRemoved(_ p: Op.SeatRemoved, _ op: GameOperation, _ actor: GameActor) {
        guard let seat = state.seat(p.seatId) else { return }
        guard state.rounds.isEmpty else { return refuse(op, actor, .seatsLocked) }
        state.seats.removeAll { $0.id == p.seatId }
        if state.dealerAnchor?.seat == p.seatId { state.dealerAnchor = nil }
        if state.config.firstDealerSeat == p.seatId { state.config.firstDealerSeat = nil }
        if state.config.scorekeeperSeat == p.seatId { state.config.scorekeeperSeat = nil }
        log(.seatRemoved(seat: seat.id, name: seat.displayName), op, actor)
    }

    private mutating func applyScorekeeperChanged(_ p: Op.ScorekeeperChanged, _ op: GameOperation, _ actor: GameActor) {
        guard state.seat(p.seatId) != nil else { return refuse(op, actor, .invalid) }
        let before = state.scorekeeper
        guard before != p.seatId else { return }
        state.config.scorekeeperSeat = p.seatId
        log(.scorekeeperChanged(before: before, after: p.seatId), op, actor)
    }

    // MARK: Rounds

    private mutating func applyRoundRecorded(_ round: Round, _ op: GameOperation, _ actor: GameActor, recordedBy: String) {
        guard isValid(round) else { return refuse(op, actor, .invalid) }
        if round.number <= state.rounds.count, round.number >= 1 {
            let existing = state.rounds[round.number - 1].round
            guard existing != round else { return } // the same round twice: nothing to resolve
            state.conflicts.append(RoundConflict(opId: op.opId, roundNumber: round.number, rejected: round, byName: actor.name, at: op.hlc.date))
            log(.duplicateRound(round: round.number), op, actor, addToFeed: false)
            return
        }
        guard round.number == state.rounds.count + 1 else { return refuse(op, actor, .unknownRound) }
        if state.status == .lobby { startImplicitly(op) }
        state.rounds.append(RoundRecord(round: round, recordedAt: op.hlc.date, recordedBy: recordedBy, opId: op.opId))
        lastTouch[round.number] = op
        if let marked = liveKnocks[round.number], marked.knocker != round.knocker {
            log(.knockerOverridden(round: round.number, marked: marked.knocker, recorded: round.knocker), op, actor, addToFeed: false)
        }
        state.feed.append(FeedEntry(opId: op.opId, hlc: op.hlc, kind: .roundSaved(round: round.number)))
    }

    private mutating func applyRoundEdited(_ round: Round, _ op: GameOperation, _ actor: GameActor) {
        guard round.number >= 1, round.number <= state.rounds.count else { return refuse(op, actor, .unknownRound) }
        guard isValid(round) else { return refuse(op, actor, .invalid) }
        let index = round.number - 1
        let old = state.rounds[index]
        guard old.round != round else { return }

        let before = currentTotals()
        var record = old
        record.round = round
        record.scores = round.scores
        record.outcome = round.outcome
        record.editCount += 1
        let seats = Set(old.round.hands.keys).union(round.hands.keys)
        let handChanges = seats
            .filter { old.round.hands[$0] != round.hands[$0] }
            .sorted { seatSortKey($0) < seatSortKey($1) }
            .map { HandChange(seat: $0, before: old.round.hands[$0] ?? 0, after: round.hands[$0] ?? 0) }
        record.editedSeats.formUnion(handChanges.map(\.seat))
        let knockerChange = old.knocker != round.knocker ? Change(before: old.knocker, after: round.knocker) : nil
        if knockerChange != nil { record.editedSeats.insert(round.knocker) }
        let outcomeChange = old.outcome != round.outcome ? Change(before: old.outcome, after: round.outcome) : nil
        state.rounds[index] = record
        lastTouch[round.number] = op

        let change = AuditChange.roundEdited(round: round.number, hands: handChanges, knocker: knockerChange, outcome: outcomeChange)
        log(change, op, actor, effects: effects(from: before, to: currentTotals()))
    }

    private mutating func applyRoundUndone(_ p: Op.RoundUndone, _ op: GameOperation, _ actor: GameActor) {
        guard p.roundNumber == state.rounds.count, p.roundNumber >= 1 else { return refuse(op, actor, .notLatestRound) }
        let before = currentTotals()
        state.rounds.removeLast()
        lastTouch[p.roundNumber] = nil
        reports[p.roundNumber] = nil
        reportOrder[p.roundNumber] = nil
        resolvedKnockers[p.roundNumber] = nil
        proposals[p.roundNumber] = nil
        log(.roundUndone(round: p.roundNumber), op, actor, effects: effects(from: before, to: currentTotals()))
    }

    private mutating func applyKnockMarked(_ p: Op.KnockMarked, _ op: GameOperation, _ actor: GameActor) {
        guard p.roundNumber == state.rounds.count + 1 else { return } // a stale mark; harmless
        guard let knocker = p.knocker else {
            liveKnocks[p.roundNumber] = nil
            return
        }
        guard state.seat(knocker) != nil else { return refuse(op, actor, .invalid) }
        let mark = LiveKnock(roundNumber: p.roundNumber, knocker: knocker, markedBy: actor.seat, markedByName: actor.name, markedAt: op.hlc.date, opId: op.opId)
        liveKnocks[p.roundNumber] = mark
        state.feed.append(FeedEntry(opId: op.opId, hlc: op.hlc, kind: .liveKnock(mark)))
    }

    private mutating func applyKnockerProposed(_ p: Op.KnockerProposed, _ op: GameOperation, _ actor: GameActor) {
        guard p.roundNumber == state.rounds.count + 1, state.seat(p.knocker) != nil else { return }
        proposals[p.roundNumber, default: []].append(
            KnockerProposal(opId: op.opId, proposer: actor.seat, proposerName: actor.name, knocker: p.knocker, at: op.hlc.date)
        )
    }

    private mutating func applyKnockerResolved(_ p: Op.KnockerResolved, _ op: GameOperation, _ actor: GameActor) {
        guard p.roundNumber == state.rounds.count + 1, state.seat(p.knocker) != nil else { return }
        resolvedKnockers[p.roundNumber] = p.knocker
        completeSelfReportIfReady(p.roundNumber, op, actor)
    }

    private mutating func applyHandReported(_ p: Op.HandReported, _ op: GameOperation, _ actor: GameActor) {
        guard p.roundNumber == state.rounds.count + 1 else { return }
        guard state.seat(p.seatId) != nil, Round.handRange.contains(p.hand) else { return refuse(op, actor, .invalid) }
        if reports[p.roundNumber]?[p.seatId] == nil {
            reportOrder[p.roundNumber, default: []].append(p.seatId)
        }
        reports[p.roundNumber, default: [:]][p.seatId] = p
        completeSelfReportIfReady(p.roundNumber, op, actor)
    }

    /// Self-report: once every seat has reported and the knocker is settled, the round is saved.
    private mutating func completeSelfReportIfReady(_ number: Int, _ op: GameOperation, _ actor: GameActor) {
        guard let roundReports = reports[number], state.seats.allSatisfy({ roundReports[$0.id] != nil }) else { return }
        let claimed = (reportOrder[number] ?? []).filter { roundReports[$0]?.knocked == true }
        guard let knocker = resolvedKnockers[number] ?? (claimed.count == 1 ? claimed.first : nil) else { return }
        let round = Round(number: number, hands: roundReports.mapValues(\.hand), knocker: knocker)
        applyRoundRecorded(round, op, actor, recordedBy: "Everyone reported")
    }

    // MARK: Game shape

    private mutating func applyRoundsChanged(_ p: Op.RoundsChanged, _ op: GameOperation, _ actor: GameActor) {
        let planned = min(max(p.plannedRounds, state.rounds.count, 1), GameConfig.plannedRoundsRange.upperBound)
        let before = state.config.plannedRounds
        guard planned != before else { return }
        state.config.plannedRounds = planned
        log(.plannedRoundsChanged(Change(before: before, after: planned)), op, actor)
    }

    private mutating func applyDealerChanged(_ p: Op.DealerChanged, _ op: GameOperation, _ actor: GameActor) {
        guard state.seat(p.dealer) != nil, p.roundNumber >= 1 else { return refuse(op, actor, .invalid) }
        let before = state.dealer(forRound: p.roundNumber)
        state.dealerAnchor = DealerAnchor(roundNumber: p.roundNumber, seat: p.dealer)
        guard before != p.dealer else { return }
        log(.dealerChanged(round: p.roundNumber, before: before, after: p.dealer), op, actor)
    }

    private mutating func applyGameFinished(_ p: Op.GameFinished, _ op: GameOperation, _ actor: GameActor) {
        if !p.finalRounds.isEmpty {
            let current = state.rounds.map(\.round)
            if current != p.finalRounds {
                // The finisher's view is authoritative. Anything this phone applied that the
                // finisher didn't see is surfaced as late (H-05).
                let numbers = Set(current.map(\.number)).union(p.finalRounds.map(\.number))
                for number in numbers.sorted() {
                    let mine = number <= current.count ? current[number - 1] : nil
                    let theirs = p.finalRounds.first { $0.number == number }
                    if mine != theirs, let touch = lastTouch[number], touch.opId != op.opId {
                        refuse(touch, resolveActor(touch), .afterFinish)
                    }
                }
                state.rounds = p.finalRounds.sorted { $0.number < $1.number }.enumerated().map { index, round in
                    var round = round
                    round.number = index + 1
                    if index < state.rounds.count, state.rounds[index].round == round {
                        return state.rounds[index]
                    }
                    let previous = index < state.rounds.count ? state.rounds[index] : nil
                    return RoundRecord(
                        round: round,
                        recordedAt: previous?.recordedAt ?? op.hlc.date,
                        recordedBy: previous?.recordedBy ?? actor.name,
                        opId: previous?.opId ?? op.opId,
                        editedSeats: previous?.editedSeats ?? [],
                        editCount: previous?.editCount ?? 0
                    )
                }
            }
        }
        state.status = .finished
        state.finishReason = p.reason
        state.finishedAt = op.hlc.date
        finishedHLC = op.hlc
        log(.finished(p.reason, afterRound: state.rounds.count), op, p.reason == .autoFinished ? .system : actor)
    }

    private mutating func applyGameAbandoned(_ op: GameOperation, _ actor: GameActor) {
        statusBeforeAbandon = state.status
        state.status = .abandoned
        state.abandonedAt = op.hlc.date
        abandonedHLC = op.hlc
        log(.abandoned, op, actor)
    }

    private mutating func applyGameRestored(_ op: GameOperation, _ actor: GameActor) {
        guard state.status == .abandoned, let abandonedHLC else { return }
        guard op.hlc.wallMs - abandonedHLC.wallMs <= GameState.restoreWindowMs else {
            return refuse(op, actor, .restoreExpired)
        }
        state.status = statusBeforeAbandon
        state.abandonedAt = nil
        self.abandonedHLC = nil
        log(.restored, op, actor)
    }

    // MARK: Trash talk

    private mutating func applyTauntSent(_ p: Op.TauntSent, _ op: GameOperation) {
        guard !state.taunts.contains(where: { $0.tauntId == p.tauntId }) else { return }
        let record = TauntRecord(
            tauntId: p.tauntId, opId: op.opId, roundNumber: p.roundNumber, from: p.from, fromName: p.fromName,
            target: p.target, content: p.content, at: op.hlc.date, isRetracted: false
        )
        state.taunts.append(record)
        state.feed.append(FeedEntry(opId: op.opId, hlc: op.hlc, kind: .taunt(record)))
    }

    private mutating func applyTauntRetracted(_ p: Op.TauntRetracted) {
        guard let index = state.taunts.firstIndex(where: { $0.tauntId == p.tauntId }) else { return }
        state.taunts[index].isRetracted = true
        state.feed.removeAll {
            if case .taunt(let taunt) = $0.kind { taunt.tauntId == p.tauntId } else { false }
        }
    }

    private mutating func applyReactionAdded(_ p: Op.ReactionAdded, _ op: GameOperation) {
        guard state.seat(p.seatId) != nil, p.roundNumber >= 1, p.roundNumber <= state.rounds.count else { return }
        state.reactions[p.roundNumber, default: [:]][p.seatId] = p.reaction
        state.feed.append(FeedEntry(opId: op.opId, hlc: op.hlc, kind: .reaction(round: p.roundNumber, seat: p.seatId, reaction: p.reaction)))
    }

    private mutating func applyReceiptSent(_ p: Op.ReceiptSent, _ op: GameOperation) {
        guard p.fromSeat != p.toSeat,
              state.seat(p.fromSeat) != nil, state.seat(p.toSeat) != nil,
              !state.receipts.contains(where: { $0.from == p.fromSeat && $0.to == p.toSeat })
        else { return }
        let record = ReceiptRecord(opId: op.opId, from: p.fromSeat, to: p.toSeat, receiptKey: p.receiptKey, at: op.hlc.date)
        state.receipts.append(record)
        state.feed.append(FeedEntry(opId: op.opId, hlc: op.hlc, kind: .receipt(record)))
    }

    // MARK: Helpers

    private mutating func startImplicitly(_ op: GameOperation) {
        state.status = .active
        state.startedAt = op.hlc.date
        if state.dealerAnchor == nil, let first = state.config.firstDealerSeat ?? state.hostSeat ?? state.seats.first?.id {
            state.dealerAnchor = DealerAnchor(roundNumber: 1, seat: first)
        }
    }

    private func isValid(_ round: Round) -> Bool {
        guard round.isValid, !state.seats.isEmpty else { return false }
        let seatIDs = Set(state.seats.map(\.id))
        return Set(round.hands.keys) == seatIDs && seatIDs.contains(round.knocker)
    }

    private func resolveActor(_ op: GameOperation) -> GameActor {
        if let player = op.actorPlayerId, let seat = state.seat(for: .player(player)) {
            return GameActor(seat: seat.id, name: seat.displayName)
        }
        if let seat = state.seat(linkedTo: op.deviceId) {
            return GameActor(seat: seat.id, name: seat.displayName)
        }
        return GameActor(seat: nil, name: "Someone")
    }

    private func currentTotals() -> [SeatID: Int] {
        var totals = Dictionary(uniqueKeysWithValues: state.seats.map { ($0.id, 0) })
        for record in state.rounds {
            for (seat, score) in record.scores { totals[seat, default: 0] += score }
        }
        return totals
    }

    private func effects(from before: [SeatID: Int], to after: [SeatID: Int]) -> [ScoreEffect] {
        state.seats.compactMap { seat in
            let old = before[seat.id] ?? 0, new = after[seat.id] ?? 0
            return old == new ? nil : ScoreEffect(seat: seat.id, before: old, after: new)
        }
    }

    private mutating func log(_ change: AuditChange, _ op: GameOperation, _ actor: GameActor, effects: [ScoreEffect] = [], addToFeed: Bool = true) {
        let names = state.seats.reduce(into: [SeatID: String]()) { $0[$1.id] = $1.displayName }
        let summary = AuditText.summary(for: change, actor: actor.name) { names[$0] ?? "Someone" }
        let entry = AuditEntry(opId: op.opId, hlc: op.hlc, actor: actor, change: change, effects: effects, summary: summary)
        state.audit.append(entry)
        if addToFeed {
            state.feed.append(FeedEntry(opId: op.opId, hlc: op.hlc, kind: .record(entry)))
        }
    }

    private mutating func refuse(_ op: GameOperation, _ actor: GameActor, _ reason: LateOperation.Reason) {
        guard !state.lateOperations.contains(where: { $0.operation.opId == op.opId }) else { return }
        state.lateOperations.append(LateOperation(operation: op, actorName: actor.name, reason: reason))
        if reason == .afterFinish || reason == .afterAbandon {
            log(.lateOperation(op.type, reason), op, actor, addToFeed: false)
        }
    }

    private func seatSort(_ lhs: Seat, _ rhs: Seat) -> Bool {
        (lhs.order, lhs.id) < (rhs.order, rhs.id)
    }

    private func seatSortKey(_ id: SeatID) -> Int {
        state.seats.firstIndex { $0.id == id } ?? .max
    }

    private mutating func sortSeats() {
        state.seats.sort(by: seatSort)
    }

    // MARK: Output

    func makeState() -> GameState {
        var result = state
        let totals = currentTotals()
        let ranks = Scoring.ranks(totals)
        let winners = Scoring.winners(totals)
        let next = result.rounds.count + 1
        let dealer = result.status.isLive ? result.dealer(forRound: next) : nil
        result.currentDealer = dealer
        let last = result.rounds.last
        let order = Scoring.ordered(totals, tieOrder: result.seats.map(\.id))
        result.standings = order.compactMap { id in
            guard let seat = result.seat(id) else { return nil }
            let lastResult = last.flatMap { record -> SeatRoundResult? in
                guard let hand = record.round.hands[id], let score = record.scores[id] else { return nil }
                let isKnocker = record.knocker == id
                return SeatRoundResult(roundNumber: record.number, hand: hand, score: score, isKnocker: isKnocker, outcome: isKnocker ? record.outcome : nil)
            }
            return Standing(
                seat: seat,
                total: totals[id] ?? 0,
                rank: ranks[id] ?? Rank(position: 1, isShared: false),
                isLeader: !result.rounds.isEmpty && winners.contains(id),
                isDealer: id == dealer,
                lastRound: lastResult
            )
        }
        result.liveKnock = result.status.isLive ? liveKnocks[next] : nil
        if result.status.isLive, let roundReports = reports[next], !roundReports.isEmpty || resolvedKnockers[next] != nil {
            let claimed = (reportOrder[next] ?? []).filter { roundReports[$0]?.knocked == true }
            result.selfReport = SelfReportRound(
                roundNumber: next,
                hands: roundReports.mapValues(\.hand),
                claimedKnockers: claimed,
                proposals: proposals[next] ?? [],
                resolvedKnocker: resolvedKnockers[next],
                waitingOn: result.seats.map(\.id).filter { roundReports[$0] == nil }
            )
        } else if result.status.isLive, let pending = proposals[next], !pending.isEmpty {
            result.selfReport = SelfReportRound(
                roundNumber: next, hands: [:], claimedKnockers: [], proposals: pending,
                resolvedKnocker: resolvedKnockers[next], waitingOn: result.seats.map(\.id)
            )
        }
        return result
    }
}
