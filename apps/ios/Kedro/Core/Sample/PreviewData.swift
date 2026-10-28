import Foundation

/// Sample data for previews, tests and the DEBUG demo seeder: the design spec's sample game
/// (§17, Cold Deck) as real operations, and a generated history for stats screens.
///
/// Everything is deterministic: fixed IDs, fixed timestamps, seeded randomness.
nonisolated enum PreviewData {
    // MARK: People

    /// A fixed UUID for sample data: `0000000k-0000-4000-8000-0000000000nn`.
    static func fixedUUID(kind: UInt8, _ number: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, kind, 0, 0, 0x40, 0, 0x80, 0, 0, 0, 0, 0, 0, number))
    }

    static func player(_ number: UInt8, _ name: String, _ handle: String, _ avatar: Avatar, title: String? = nil, games: Int? = nil) -> PlayerSummary {
        PlayerSummary(
            id: PlayerID(fixedUUID(kind: 1, number)),
            displayName: name,
            handle: Handle(constant: handle),
            avatar: avatar,
            titleID: title,
            gamesPlayed: games
        )
    }

    /// Noah is the demo "you" (the DEBUG test user signs in as Noah).
    static let noah = player(1, "Noah", "noah", .curated(.crow), title: "TI-12", games: 40)
    static let ana = player(2, "Ana", "ana.k", .emoji("🦊", colorIndex: 0), title: "TI-14", games: 30)
    static let ben = player(3, "Ben", "ben", .curated(.bull), title: "TI-01", games: 4)
    static let cleo = player(4, "Cleo", "cleo", .curated(.joker), title: "TI-13", games: 12)
    static let priya = player(5, "Priya", "priya", .emoji("🦂", colorIndex: 1), games: 18)
    static let jo = player(6, "Jo", "jo.b", .curated(.wolf), games: 8)
    static let max = player(7, "Max", "max", .curated(.shark), games: 14)
    static let maya = player(8, "Maya", "maya", .emoji("🐍", colorIndex: 2), games: 22)
    static let theo = player(9, "Theo", "theo", .curated(.skull), games: 9)
    static let leo = player(10, "Leo", "leo.r", .emoji("🦉", colorIndex: 3), games: 6)

    /// Sam is a guest on their 3rd game.
    static let samID = GuestID(fixedUUID(kind: 2, 1))

    static let players = [noah, ana, ben, cleo, priya, jo, max, maya, theo, leo]

    static let noahPhone = DeviceID(fixedUUID(kind: 3, 1))
    static let anaPhone = DeviceID(fixedUUID(kind: 3, 2))

    /// The identity of Noah's phone.
    static let noahIdentity = LocalIdentity(deviceID: noahPhone, player: noah.ref, displayName: "Noah")

    static let noahProfile = LocalProfile(identity: noah.ref, displayName: "Noah", handle: noah.handle, avatar: noah.avatar, titleID: noah.titleID)

    // MARK: The sample game (design §17)

    static let sampleGameID = GameID(fixedUUID(kind: 4, 1))
    /// 2026-10-24 21:00 UTC.
    static let sampleStartMs: Int64 = 1_792_875_600_000

    static var sampleSeats: [Seat] {
        [
            Seat(noah, order: 0, deviceID: noahPhone, languageLevel: .unhinged),
            Seat(ana, order: 1, deviceID: anaPhone, languageLevel: .unhinged),
            Seat(ben, order: 2, languageLevel: .unhinged),
            Seat(cleo, order: 3, languageLevel: .unhinged),
            Seat(player: .guest(samID), displayName: "Sam", order: 4, gamesPlayed: 2),
        ]
    }

    static var noahSeat: SeatID { noah.seatID }
    static var anaSeat: SeatID { ana.seatID }
    static var benSeat: SeatID { ben.seatID }
    static var cleoSeat: SeatID { cleo.seatID }
    static var samSeat: SeatID { PlayerRef.guest(samID).seatID }

    /// Rounds R1–R8 exactly as in design §17: (knocker, hands for Noah, Ana, Ben, Cleo, Sam).
    static var sampleRounds: [Round] {
        let table: [(SeatID, [Int])] = [
            (anaSeat, [9, 3, 12, 7, 15]),
            (benSeat, [6, 11, 5, 5, 20]),
            (noahSeat, [8, 3, 14, 10, 9]),
            (cleoSeat, [3, 16, 7, 2, -1]),
            (noahSeat, [2, 9, 6, 11, 4]),
            (samSeat, [7, 2, 9, 8, 1]),
            (anaSeat, [5, 2, 2, 6, 12]),
            (noahSeat, [0, 1, 12, 6, 21]),
        ]
        let order = [noahSeat, anaSeat, benSeat, cleoSeat, samSeat]
        return table.enumerated().map { index, row in
            Round(number: index + 1, hands: Dictionary(uniqueKeysWithValues: zip(order, row.1)), knocker: row.0)
        }
    }

    /// The sample game's operations.
    ///
    /// - Parameters:
    ///   - throughRound: Rounds saved (0–8). The plan is 6 rounds, extended to 8 after Round 6.
    ///   - finished: Append `GameFinished` (only meaningful with all 8 rounds).
    ///   - liveKnock: Mark Sam's live knock for the next round (as in mockup frame 9).
    static func sampleOperations(throughRound: Int = 8, finished: Bool = true, liveKnock: Bool = false) -> [GameOperation] {
        var builder = OperationBuilder(gameID: sampleGameID, device: noahPhone, actor: noah.id, startMs: sampleStartMs)
        builder.add(.gameCreated(.init(config: GameConfig(plannedRounds: 6, scoringMode: .scorekeeper, tableWord: "Cold Deck", firstDealerSeat: noahSeat, scorekeeperSeat: noahSeat), host: noahSeat)))
        for seat in sampleSeats {
            builder.add(.playerSeated(.init(seat: seat)))
        }
        builder.add(.gameStarted(.init(seatOrder: sampleSeats.map(\.id), firstDealer: noahSeat)))
        let rounds = sampleRounds.prefix(Swift.max(0, Swift.min(throughRound, 8)))
        for round in rounds {
            builder.advance(minutes: 4)
            builder.add(.roundRecorded(.init(round: round)))
            if round.number == 5 {
                // Reactions on Round 5 (mockup frame 6), from the phones at the table.
                builder.add(.reactionAdded(.init(roundNumber: 5, seatId: anaSeat, reaction: .fire)), device: anaPhone, actor: ana.id)
                builder.add(.reactionAdded(.init(roundNumber: 5, seatId: noahSeat, reaction: .skull)))
            }
            if round.number == 6 {
                builder.add(.roundsChanged(.init(plannedRounds: 8)))
            }
        }
        if liveKnock, rounds.count < 8 {
            builder.advance(minutes: 2)
            builder.add(.knockMarked(.init(roundNumber: rounds.count + 1, knocker: samSeat)), device: anaPhone, actor: ana.id)
            builder.add(.tauntSent(.init(tauntId: fixedUUID(kind: 5, 1), roundNumber: rounds.count + 1, from: anaSeat, fromName: "Ana", target: .seat(samSeat), content: .canned(id: "TT-01"))), device: anaPhone, actor: ana.id)
        }
        if finished, rounds.count == 8 {
            builder.advance(minutes: 1)
            builder.add(.gameFinished(.init(reason: .completed, finalRounds: Array(rounds))))
        }
        return builder.operations
    }

    /// The sample game folded: after Round 5 (the mockups' Table) by default.
    static func sampleState(throughRound: Int = 5, finished: Bool = false) -> GameState {
        GameState.fold(sampleOperations(throughRound: throughRound, finished: finished), gameID: sampleGameID)
    }

    /// A session on Noah's phone backed by an in-memory store (previews).
    @MainActor
    static func sampleSession(throughRound: Int = 5, finished: Bool = false, liveKnock: Bool = false) -> GameSession {
        let operations = sampleOperations(throughRound: throughRound, finished: finished, liveKnock: liveKnock)
        return GameSession(
            gameID: sampleGameID,
            operations: operations,
            store: InMemoryGameStore(operations: operations),
            transport: LocalOnlyTransport(),
            identity: noahIdentity,
            clock: HybridLogicalClock(device: noahPhone)
        )
    }
}

/// Builds a sequence of operations with increasing HLCs.
nonisolated struct OperationBuilder {
    let gameID: GameID
    let device: DeviceID
    let actor: PlayerID?
    private(set) var wallMs: Int64
    private var counter = 0
    private(set) var operations: [GameOperation] = []
    private var sequence: UInt32 = 0

    init(gameID: GameID, device: DeviceID, actor: PlayerID?, startMs: Int64) {
        self.gameID = gameID
        self.device = device
        self.actor = actor
        wallMs = startMs
    }

    mutating func advance(minutes: Double) {
        wallMs += Int64(minutes * 60_000)
        counter = 0
    }

    mutating func add(_ payload: OperationPayload, device: DeviceID? = nil, actor: PlayerID?? = nil) {
        wallMs += 1_000
        sequence += 1
        let deviceID = device ?? self.device
        operations.append(GameOperation(
            opId: Self.opID(game: gameID, sequence: sequence),
            gameId: gameID,
            deviceId: deviceID,
            hlc: HLC(wallMs: wallMs, counter: counter, node: deviceID.uuidString),
            actorPlayerId: actor ?? self.actor,
            payload: payload
        ))
    }

    /// Deterministic operation IDs: the game's UUID with the sequence in bytes 8–11 (sample game
    /// IDs only use bytes 3 and 15, so op IDs never collide across games).
    private static func opID(game: GameID, sequence: UInt32) -> UUID {
        var bytes = game.rawValue.uuid
        bytes.8 = 0xA0 | UInt8(truncatingIfNeeded: sequence >> 24) & 0x0F
        bytes.9 = UInt8(truncatingIfNeeded: sequence >> 16)
        bytes.10 = UInt8(truncatingIfNeeded: sequence >> 8)
        bytes.11 = UInt8(truncatingIfNeeded: sequence)
        return UUID(uuid: bytes)
    }
}
