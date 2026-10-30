import Foundation

/// Where a game is in its life. JSON: `"lobby"` | `"active"` | `"finished"` | `"abandoned"`.
nonisolated enum GameStatus: String, Hashable, Sendable, Codable {
    /// Seats are being filled; nobody has tapped Deal.
    case lobby
    /// Rounds are being played.
    case active
    /// Locked. Immutable (PRD §4.5).
    case finished
    /// Voided: stays in history, excluded from all stats (PRD §4.6).
    case abandoned

    /// Lobby or active.
    var isLive: Bool { self == .lobby || self == .active }
}

/// Everything a table shows, derived from the operation log by `GameState.fold(_:)`.
///
/// Never mutate a `GameState` to change a game: append an operation (`GameSession.send`) and the
/// state is re-folded. This keeps every phone identical (one source of truth).
nonisolated struct GameState: Hashable, Sendable {
    let gameID: GameID
    var config: GameConfig
    var status: GameStatus
    var hostSeat: SeatID?
    /// Seats in clockwise order (also the dealing order).
    var seats: [Seat]
    /// Saved rounds, ascending, numbered 1…n with no gaps.
    var rounds: [RoundRecord]
    /// Best (lowest total) first; equal totals keep seat order.
    var standings: [Standing]
    /// Who deals the next round (lobby and active games). nil once the game is over or before
    /// anyone is seated.
    var currentDealer: SeatID?
    /// Where the deal rotation is anchored: Round 1's first dealer, or the latest `DealerChanged`.
    var dealerAnchor: DealerAnchor?
    /// The live knock for the round being played, if someone marked one (design §7.5).
    var liveKnock: LiveKnock?
    /// Self-report progress for the round being played (design §7.4). nil in scorekeeper mode
    /// when nothing has been reported.
    var selfReport: SelfReportRound?
    /// Reactions by round, then by the reacting seat (one each).
    var reactions: [Int: [SeatID: Reaction]]
    /// Taunts in order, including retracted ones (`isRetracted`), which UIs must hide.
    var taunts: [TauntRecord]
    var receipts: [ReceiptRecord]
    /// "On the record": every logged change, oldest first (PRD §4.5).
    var audit: [AuditEntry]
    /// The game's chronological feed (design §8.4), oldest first.
    var feed: [FeedEntry]
    /// Rounds recorded twice: the earlier is kept, the other offered as "Use this version" (H-06).
    var conflicts: [RoundConflict]
    /// Operations that were refused (after finish, after abandon, seats locked…); surfaced with H-05.
    var lateOperations: [LateOperation]
    /// The phone that plays the shared sounds, if one claimed it (design §3.8).
    var tableSpeaker: DeviceID?
    var createdAt: Date?
    var startedAt: Date?
    var finishedAt: Date?
    var finishReason: FinishReason?
    var abandonedAt: Date?
    /// The HLC of the newest operation folded in (for `GET /v1/games/:id/ops?after=`).
    var latestHLC: HLC?

    init(gameID: GameID) {
        self.gameID = gameID
        config = GameConfig(tableWord: "Cold Deck")
        status = .lobby
        seats = []
        rounds = []
        standings = []
        reactions = [:]
        taunts = []
        receipts = []
        audit = []
        feed = []
        conflicts = []
        lateOperations = []
    }

    // MARK: Lookups

    func seat(_ id: SeatID) -> Seat? { seats.first { $0.id == id } }

    func standing(for id: SeatID) -> Standing? { standings.first { $0.id == id } }

    /// The seat a person occupies, if they're at this table.
    func seat(for player: PlayerRef) -> Seat? { seat(player.seatID) }

    /// The seat linked to a phone.
    func seat(linkedTo device: DeviceID) -> Seat? { seats.first { $0.deviceID == device } }

    func round(_ number: Int) -> RoundRecord? {
        guard number >= 1, number <= rounds.count else { return nil }
        return rounds[number - 1]
    }

    /// Display name for a seat ("Someone" if it isn't at the table).
    func name(of id: SeatID) -> String { seat(id)?.displayName ?? "Someone" }

    // MARK: Derived

    var lastRound: RoundRecord? { rounds.last }

    /// The round being played next (1-based).
    var nextRoundNumber: Int { rounds.count + 1 }

    var progress: GameProgress {
        GameProgress(completedRounds: rounds.count, plannedRounds: config.plannedRounds)
    }

    /// Cumulative totals by seat.
    var totals: [SeatID: Int] { Dictionary(uniqueKeysWithValues: standings.map { ($0.id, $0.total) }) }

    /// Seats leading (or sharing the lead). Empty before Round 1.
    var leaders: [SeatID] { rounds.isEmpty ? [] : standings.filter(\.isLeader).map(\.id) }

    /// Winners (ties share). Only meaningful once finished.
    var winners: [SeatID] { status == .finished ? leaders : [] }

    /// True when the last planned round is saved and the game isn't locked yet: show the finish
    /// gate (G-01).
    var isAwaitingFinish: Bool { status == .active && progress.isComplete }

    /// The house voice for shared surfaces (design §4.1).
    var houseLevel: LanguageLevel {
        LanguageLevel.house(seated: seats.compactMap(\.languageLevel), cap: config.houseVoiceCap)
    }

    /// The scorekeeper (scorekeeper mode): the configured seat, else the host.
    var scorekeeper: SeatID? { config.scorekeeperSeat ?? hostSeat }

    /// Who deals a given round, from the anchor and the clockwise seat order.
    func dealer(forRound round: Int) -> SeatID? {
        guard !seats.isEmpty else { return nil }
        let anchor = dealerAnchor ?? DealerAnchor(roundNumber: 1, seat: config.firstDealerSeat ?? hostSeat ?? seats[0].id)
        let anchorIndex = seats.firstIndex { $0.id == anchor.seat } ?? 0
        let count = seats.count
        let offset = ((round - anchor.roundNumber) % count + count) % count
        return seats[(anchorIndex + offset) % count].id
    }

    /// Reaction counts for a round, in `Reaction.allCases` order.
    func reactionCounts(forRound round: Int) -> [(reaction: Reaction, count: Int)] {
        let byReaction = Dictionary(grouping: (reactions[round] ?? [:]).values, by: { $0 }).mapValues(\.count)
        return Reaction.allCases.map { ($0, byReaction[$0] ?? 0) }
    }

    /// Taunts that should be shown (not retracted).
    var visibleTaunts: [TauntRecord] { taunts.filter { !$0.isRetracted } }
}

/// Round progress: "ROUND 6 OF 8".
nonisolated struct GameProgress: Hashable, Sendable {
    var completedRounds: Int
    var plannedRounds: Int

    /// The round being played (or the last one, once all are in).
    var currentRound: Int { min(completedRounds + 1, max(plannedRounds, 1)) }
    var isComplete: Bool { completedRounds >= plannedRounds }
    var remainingRounds: Int { max(0, plannedRounds - completedRounds) }
    var fraction: Double { plannedRounds > 0 ? min(1, Double(completedRounds) / Double(plannedRounds)) : 0 }
}

/// A saved round plus how it got there.
nonisolated struct RoundRecord: Hashable, Sendable, Identifiable {
    var round: Round
    var scores: [SeatID: Int]
    var outcome: KnockOutcome?
    var recordedAt: Date
    /// Who saved it (a seat's name, or "Everyone reported").
    var recordedBy: String
    /// The operation that created it.
    var opId: UUID
    /// Seats whose hand was changed by an edit (History's "Edited" tags), plus the knocker if
    /// the knocker changed.
    var editedSeats: Set<SeatID>
    var editCount: Int

    var id: Int { round.number }
    var number: Int { round.number }
    var knocker: SeatID { round.knocker }
    var isEdited: Bool { editCount > 0 }

    init(round: Round, recordedAt: Date, recordedBy: String, opId: UUID, editedSeats: Set<SeatID> = [], editCount: Int = 0) {
        self.round = round
        scores = round.scores
        outcome = round.outcome
        self.recordedAt = recordedAt
        self.recordedBy = recordedBy
        self.opId = opId
        self.editedSeats = editedSeats
        self.editCount = editCount
    }

    /// True when a red King decided the round: the knocker's or the winning hand is negative.
    var redKingDecided: Bool {
        guard let lowest = round.hands.values.min() else { return false }
        return lowest < 0
    }
}

/// One row of the standings.
nonisolated struct Standing: Hashable, Sendable, Identifiable {
    var seat: Seat
    var total: Int
    var rank: Rank
    var isLeader: Bool
    var isDealer: Bool
    /// This seat's part in the most recent round.
    var lastRound: SeatRoundResult?

    var id: SeatID { seat.id }
}

/// One seat's result in one round, for deltas ("landed · −10", "+9").
nonisolated struct SeatRoundResult: Hashable, Sendable {
    var roundNumber: Int
    var hand: Int
    var score: Int
    var isKnocker: Bool
    /// Set only for the knocker.
    var outcome: KnockOutcome?
}

/// Anchors the deal rotation: `seat` deals `roundNumber`, and the deal passes left from there.
nonisolated struct DealerAnchor: Hashable, Sendable {
    var roundNumber: Int
    var seat: SeatID
}

nonisolated struct LiveKnock: Hashable, Sendable {
    var roundNumber: Int
    var knocker: SeatID
    var markedBy: SeatID?
    var markedByName: String
    var markedAt: Date
    var opId: UUID
}

/// Self-report progress for one round (design §7.4).
nonisolated struct SelfReportRound: Hashable, Sendable {
    var roundNumber: Int
    /// Hands reported so far.
    var hands: [SeatID: Int]
    /// Seats that said "I knocked".
    var claimedKnockers: [SeatID]
    var proposals: [KnockerProposal]
    var resolvedKnocker: SeatID?
    /// Seats still to report, in seat order.
    var waitingOn: [SeatID]

    /// The knocker if settled: resolved, or exactly one claim.
    var knocker: SeatID? {
        resolvedKnocker ?? (claimedKnockers.count == 1 ? claimedKnockers.first : nil)
    }

    /// Ask "Who knocked?" once everyone has reported and nobody or several claimed it (K-15/K-16).
    var needsKnockerDecision: Bool { waitingOn.isEmpty && knocker == nil }
}

nonisolated struct KnockerProposal: Hashable, Sendable, Identifiable {
    var opId: UUID
    var proposer: SeatID?
    var proposerName: String
    var knocker: SeatID
    var at: Date

    var id: UUID { opId }
}

nonisolated struct TauntRecord: Hashable, Sendable, Identifiable {
    var tauntId: UUID
    var opId: UUID
    var roundNumber: Int
    var from: SeatID?
    var fromName: String
    var target: TauntTarget
    var content: TauntContent
    var at: Date
    var isRetracted: Bool

    var id: UUID { tauntId }
}

nonisolated struct ReceiptRecord: Hashable, Sendable, Identifiable {
    var opId: UUID
    var from: SeatID
    var to: SeatID
    var receiptKey: String
    var at: Date

    var id: UUID { opId }
}

/// A round recorded twice. `rejected` is the version that wasn't applied ("Use this version").
nonisolated struct RoundConflict: Hashable, Sendable, Identifiable {
    var opId: UUID
    var roundNumber: Int
    var rejected: Round
    var byName: String
    var at: Date

    var id: UUID { opId }
}

/// An operation the fold refused.
nonisolated struct LateOperation: Hashable, Sendable, Identifiable {
    enum Reason: String, Hashable, Sendable {
        /// Arrived for a finished game (H-05).
        case afterFinish
        /// Arrived for an abandoned game.
        case afterAbandon
        /// Seats are fixed after Round 1.
        case seatsLocked
        /// Lobby settings (`GameConfigured`) that arrived after Deal.
        case afterDeal
        /// A ninth seat.
        case tableFull
        /// Undo of a round that isn't the latest.
        case notLatestRound
        /// A round number that doesn't exist or skips ahead.
        case unknownRound
        /// References a seat that isn't at the table, or values out of range.
        case invalid
        /// A restore more than 15 minutes after the abandon.
        case restoreExpired
    }

    var operation: GameOperation
    var actorName: String
    var reason: Reason

    var id: UUID { operation.opId }
}
