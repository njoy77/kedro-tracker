import Foundation
import Observation

/// Who is acting on this phone.
nonisolated struct LocalIdentity: Hashable, Sendable {
    var deviceID: DeviceID
    /// The person using the phone; nil for a phone that hasn't set up a profile.
    var player: PlayerRef?
    var displayName: String

    /// `Operation.actorPlayerId`: set only for signed-in players.
    var actorPlayerID: PlayerID? { player?.playerID }
}

/// A live (or read-only historical) game on this phone. Owns the folded `state`, appends new
/// operations through the `GameStore`, sends them through the `OperationTransport`, and folds in
/// operations from other phones.
///
/// Lifecycle: create it, then run `await session.run()` from a `.task` (or keep it running in
/// `AppModel` for the live game). Every helper (`recordRound`, `editRound`, …) is a thin
/// wrapper over `send(_:)`.
@Observable
final class GameSession: Identifiable {
    enum SessionError: LocalizedError, Equatable {
        /// The game is finished or abandoned (H-04).
        case gameLocked
        /// The round isn't valid for this table (missing hands, unknown knocker, out of range).
        case invalidRound
        case nothingToUndo

        var errorDescription: String? {
            switch self {
            case .gameLocked: "Final. Locked. Complain all you want; it's not changing."
            case .invalidRound: "That round is missing a hand or a knocker."
            case .nothingToUndo: "There's nothing to undo."
            }
        }
    }

    let gameID: GameID
    private(set) var state: GameState
    /// Every operation folded so far, in fold order.
    private(set) var operations: [GameOperation]
    let identity: LocalIdentity

    @ObservationIgnored private let store: any GameStore
    @ObservationIgnored private let transport: any OperationTransport
    @ObservationIgnored private let clock: HybridLogicalClock
    @ObservationIgnored private var knownOpIDs: Set<UUID>

    var id: GameID { gameID }

    init(
        gameID: GameID,
        operations: [GameOperation] = [],
        store: any GameStore,
        transport: any OperationTransport,
        identity: LocalIdentity,
        clock: HybridLogicalClock
    ) {
        self.gameID = gameID
        let ordered = operations.filter { $0.gameId == gameID }.sorted(by: GameOperation.foldOrder)
        self.operations = ordered
        knownOpIDs = Set(ordered.map(\.opId))
        state = GameState.fold(ordered, gameID: gameID)
        self.store = store
        self.transport = transport
        self.identity = identity
        self.clock = clock
    }

    // MARK: Who am I here

    /// This phone's seat, if its person is seated.
    var mySeat: Seat? {
        if let player = identity.player, let seat = state.seat(for: player) { return seat }
        return state.seat(linkedTo: identity.deviceID)
    }

    var mySeatID: SeatID? { mySeat?.id }

    /// Watchers (not seated) can only taunt; finished and abandoned games are read-only.
    var canEdit: Bool { state.status.isLive && mySeat != nil }

    var isScorekeeper: Bool { mySeatID != nil && mySeatID == state.scorekeeper }

    // MARK: Running

    /// Loads stored operations, then folds in new ones from the store and the transport until
    /// the calling task is cancelled.
    func run() async {
        await transport.connect(to: gameID)
        if let stored = try? await store.operations(for: gameID) {
            merge(stored)
        }
        await withDiscardingTaskGroup { group in
            group.addTask { await self.foldStoreUpdates() }
            group.addTask { await self.storeIncomingOperations() }
        }
        await transport.disconnect(from: gameID)
    }

    private func foldStoreUpdates() async {
        for await batch in store.updates(for: gameID) {
            merge(batch)
        }
    }

    private func storeIncomingOperations() async {
        for await batch in transport.incoming(for: gameID) {
            for operation in batch { clock.receive(operation.hlc) }
            _ = try? await store.append(batch)
        }
    }

    /// Folds in operations (from any source). Duplicates are ignored.
    func merge(_ incoming: [GameOperation]) {
        let new = incoming.filter { $0.gameId == gameID && knownOpIDs.insert($0.opId).inserted }
        guard !new.isEmpty else { return }
        for operation in new { clock.receive(operation.hlc) }
        operations = (operations + new).sorted(by: GameOperation.foldOrder)
        state = GameState.fold(operations, gameID: gameID)
    }

    // MARK: Sending

    /// Creates an operation for this phone, folds it in immediately, stores it, and sends it.
    @discardableResult
    func send(_ payload: OperationPayload) async throws -> GameOperation {
        let operation = makeOperation(payload)
        merge([operation])
        try await store.append([operation])
        await transport.send([operation])
        return operation
    }

    /// What the game would look like with a payload applied, without sending it (the
    /// "What changes" preview before Save Change, design §9.2).
    func preview(_ payload: OperationPayload) -> GameState {
        GameState.fold(operations + [makeOperation(payload)], gameID: gameID)
    }

    private func makeOperation(_ payload: OperationPayload) -> GameOperation {
        GameOperation(
            gameId: gameID,
            deviceId: identity.deviceID,
            hlc: clock.tick(),
            actorPlayerId: identity.actorPlayerID,
            payload: payload
        )
    }

    // MARK: Rounds

    /// Saves the next round (scorekeeper mode).
    @discardableResult
    /// - Parameter inherent: The knocker went out with an inherent knock (all four cards played;
    ///   their hand must be 0).
    func recordRound(hands: [SeatID: Int], knocker: SeatID, inherent: Bool = false) async throws -> GameOperation {
        try requireLive()
        let round = Round(number: state.nextRoundNumber, hands: hands, knocker: knocker, isInherent: inherent)
        try requireValid(round)
        return try await send(.roundRecorded(.init(round: round)))
    }

    /// Corrects a saved round (any player, until the game is finished).
    @discardableResult
    func editRound(_ number: Int, hands: [SeatID: Int], knocker: SeatID, inherent: Bool = false) async throws -> GameOperation {
        try requireLive()
        let round = Round(number: number, hands: hands, knocker: knocker, isInherent: inherent)
        try requireValid(round)
        guard state.round(number) != nil else { throw SessionError.invalidRound }
        return try await send(.roundEdited(.init(round: round)))
    }

    /// Undoes the latest round (the 5-second "Round 6 saved · Undo" toast). The deal moves back.
    @discardableResult
    func undoLastRound() async throws -> GameOperation {
        try requireLive()
        guard let last = state.lastRound else { throw SessionError.nothingToUndo }
        return try await send(.roundUndone(.init(roundNumber: last.number)))
    }

    /// True if this phone may undo an "On the record" entry: its author, while the game is live,
    /// for round edits (design §9.2).
    func canUndo(_ entry: AuditEntry) -> Bool {
        guard state.status.isLive, entry.actor.seat != nil, entry.actor.seat == mySeatID else { return false }
        if case .roundEdited = entry.change { return true }
        return false
    }

    /// Reverts a round edit by saving the round's previous values as a new edit.
    @discardableResult
    func undo(_ entry: AuditEntry) async throws -> GameOperation {
        guard canUndo(entry), case let .roundEdited(number, handChanges, knocker, _) = entry.change,
              let current = state.round(number)
        else { throw SessionError.nothingToUndo }
        var hands = current.round.hands
        for change in handChanges { hands[change.seat] = change.before }
        guard let previousKnocker = knocker?.before ?? current.knocker else { throw SessionError.nothingToUndo }
        // The knock type isn't in the audit entry; it stays inherent only if the knocker didn't change.
        return try await editRound(number, hands: hands, knocker: previousKnocker, inherent: knocker == nil && current.round.isInherentKnock)
    }

    /// "Use this version" on a duplicate round (H-06).
    @discardableResult
    func useConflictVersion(_ conflict: RoundConflict) async throws -> GameOperation {
        guard let knocker = conflict.rejected.knocker else { throw SessionError.invalidRound }
        return try await editRound(conflict.roundNumber, hands: conflict.rejected.hands, knocker: knocker, inherent: conflict.rejected.isInherentKnock)
    }

    // MARK: Knocks and self-report

    /// Marks (or clears, with nil) the live knock for the round being played.
    @discardableResult
    func markKnock(_ knocker: SeatID?) async throws -> GameOperation {
        try requireLive()
        return try await send(.knockMarked(.init(roundNumber: state.nextRoundNumber, knocker: knocker)))
    }

    /// Self-report: one seat's hand for the round being played.
    @discardableResult
    /// - Parameter inherent: They went out with an inherent knock (hand 0, and `knocked`).
    func reportHand(_ hand: Int, knocked: Bool, inherent: Bool = false, for seat: SeatID) async throws -> GameOperation {
        try requireLive()
        guard Round.handRange.contains(hand), state.seat(seat) != nil, !inherent || (knocked && hand == 0) else { throw SessionError.invalidRound }
        return try await send(.handReported(.init(roundNumber: state.nextRoundNumber, seatId: seat, hand: hand, knocked: knocked, inherent: inherent ? true : nil)))
    }

    @discardableResult
    func proposeKnocker(_ knocker: SeatID) async throws -> GameOperation {
        try requireLive()
        return try await send(.knockerProposed(.init(roundNumber: state.nextRoundNumber, knocker: knocker)))
    }

    @discardableResult
    func resolveKnocker(_ knocker: SeatID) async throws -> GameOperation {
        try requireLive()
        return try await send(.knockerResolved(.init(roundNumber: state.nextRoundNumber, knocker: knocker)))
    }

    // MARK: Game shape

    /// Who deals the round being played (logged).
    @discardableResult
    func changeDealer(to seat: SeatID) async throws -> GameOperation {
        try requireLive()
        return try await send(.dealerChanged(.init(roundNumber: state.nextRoundNumber, dealer: seat)))
    }

    /// Extend: add rounds to the plan (logged).
    @discardableResult
    func extendRounds(by count: Int) async throws -> GameOperation {
        try requireLive()
        return try await send(.roundsChanged(.init(plannedRounds: state.config.plannedRounds + count)))
    }

    @discardableResult
    func handOffScorekeeping(to seat: SeatID) async throws -> GameOperation {
        try requireLive()
        return try await send(.scorekeeperChanged(.init(seatId: seat)))
    }

    /// Finish Game (all planned rounds played) or End Early. Locks the game.
    @discardableResult
    func finish(reason: FinishReason? = nil) async throws -> GameOperation {
        try requireLive()
        let reason = reason ?? (state.progress.isComplete ? .completed : .endedEarly)
        return try await send(.gameFinished(.init(reason: reason, finalRounds: state.rounds.map(\.round))))
    }

    /// Auto-finishes a game whose last planned round has sat unconfirmed for 15 minutes (G-02).
    /// Call periodically from the Table; returns nil if it isn't time yet.
    @discardableResult
    func finishIfIdle(now: Date = .now) async throws -> GameOperation? {
        guard state.isAwaitingFinish, let latest = state.latestHLC,
              now.timeIntervalSince(latest.date) >= TimeInterval(GameState.restoreWindowMs / 1000)
        else { return nil }
        return try await finish(reason: .autoFinished)
    }

    /// Voids the game for stats (restorable for 15 minutes).
    @discardableResult
    func abandon() async throws -> GameOperation {
        guard state.status != .abandoned else { throw SessionError.gameLocked }
        return try await send(.gameAbandoned(.init()))
    }

    /// True while an abandon can still be undone.
    func canRestore(now: Date = .now) -> Bool {
        guard state.status == .abandoned, let abandonedAt = state.abandonedAt else { return false }
        return now.timeIntervalSince(abandonedAt) <= TimeInterval(GameState.restoreWindowMs / 1000)
    }

    @discardableResult
    func restore() async throws -> GameOperation {
        guard canRestore() else { throw SessionError.gameLocked }
        return try await send(.gameRestored(.init()))
    }

    // MARK: Trash talk

    @discardableResult
    func sendTaunt(_ content: TauntContent, to target: TauntTarget) async throws -> GameOperation {
        guard state.status.isLive else { throw SessionError.gameLocked }
        return try await send(.tauntSent(.init(
            tauntId: UUID(),
            roundNumber: state.nextRoundNumber,
            from: mySeatID,
            fromName: mySeat?.displayName ?? identity.displayName,
            target: target,
            content: content
        )))
    }

    /// Reacts to the latest round (one reaction per player per round; a new one replaces it).
    @discardableResult
    func react(_ reaction: Reaction) async throws -> GameOperation {
        guard let seat = mySeatID, let round = state.lastRound?.number else { throw SessionError.invalidRound }
        return try await send(.reactionAdded(.init(roundNumber: round, seatId: seat, reaction: reaction)))
    }

    /// "Be the table speaker".
    @discardableResult
    func claimTableSpeaker() async throws -> GameOperation {
        try await send(.tableSpeakerClaimed(.init(deviceId: identity.deviceID)))
    }

    /// Sends a receipt to another seat after the game (one per rival per game).
    @discardableResult
    func sendReceipt(_ receiptKey: String, to seat: SeatID) async throws -> GameOperation {
        guard let me = mySeatID, state.status == .finished, me != seat else { throw SessionError.invalidRound }
        return try await send(.receiptSent(.init(fromSeat: me, toSeat: seat, receiptKey: receiptKey)))
    }

    // MARK: Guards

    private func requireLive() throws {
        guard state.status.isLive else { throw SessionError.gameLocked }
    }

    private func requireValid(_ round: Round) throws {
        // A late joiner isn't in rounds from before they sat down.
        let seats = Set(state.seats(inRound: round.number).map(\.id))
        guard round.isValid, Set(round.hands.keys) == seats, let knocker = round.knocker, seats.contains(knocker) else {
            throw SessionError.invalidRound
        }
    }
}

extension GameSession {
    /// Creates a new game: `GameCreated` plus a seat for each person, in order. Returns the
    /// session; call `start(firstDealer:)` when the host taps Deal.
    static func create(
        config: GameConfig,
        host: Seat,
        others: [Seat] = [],
        store: any GameStore,
        transport: any OperationTransport,
        identity: LocalIdentity,
        clock: HybridLogicalClock
    ) async throws -> GameSession {
        let session = GameSession(gameID: GameID(), store: store, transport: transport, identity: identity, clock: clock)
        try await session.send(.gameCreated(.init(config: config, host: host.id)))
        for (index, seat) in ([host] + others).enumerated() {
            var seat = seat
            seat.order = index
            try await session.send(.playerSeated(.init(seat: seat)))
        }
        return session
    }

    /// Deal: fixes the seat order and first dealer; every phone flips into the Table.
    @discardableResult
    func start(firstDealer: SeatID? = nil) async throws -> GameOperation {
        guard state.status == .lobby else { throw SessionError.gameLocked }
        let order = state.seats.map(\.id)
        guard let dealer = firstDealer ?? state.config.firstDealerSeat ?? state.hostSeat ?? order.first else {
            throw SessionError.invalidRound
        }
        return try await send(.gameStarted(.init(seatOrder: order, firstDealer: dealer)))
    }
}
