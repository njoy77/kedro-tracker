import Foundation
@testable import Kedro

/// Builds operation logs for fold tests: N seated players, explicit devices and wall clocks.
struct TestGame {
    let gameID = GameID()
    let seats: [Seat]
    let deviceA = DeviceID()
    let deviceB = DeviceID()
    private(set) var operations: [GameOperation] = []
    private(set) var wallMs: Int64 = 1_761_000_000_000

    init(players: Int = 3) {
        seats = (0..<players).map { index in
            Seat(player: .player(PlayerID()), displayName: "P\(index)", order: index, handle: Handle(constant: "player\(index)"))
        }
    }

    func seat(_ index: Int) -> SeatID { seats[index].id }

    /// The seat's player ID (for `actorPlayerId`).
    func player(_ index: Int) -> PlayerID? { seats[index].player.playerID }

    func round(_ number: Int, _ hands: [Int], knocker: Int) -> Round {
        Round(number: number, hands: Dictionary(uniqueKeysWithValues: zip(seats.map(\.id), hands)), knocker: seat(knocker))
    }

    var state: GameState { GameState.fold(operations, gameID: gameID) }

    /// Appends an operation. Each call advances the wall clock by a second unless `at` is given.
    @discardableResult
    mutating func add(_ payload: OperationPayload, device: DeviceID? = nil, at wall: Int64? = nil, actor: Int? = 0) -> GameOperation {
        if let wall { wallMs = wall } else { wallMs += 1_000 }
        let deviceID = device ?? deviceA
        let operation = GameOperation(
            gameId: gameID,
            deviceId: deviceID,
            hlc: HLC(wallMs: wallMs, counter: 0, node: deviceID.uuidString),
            actorPlayerId: actor.flatMap { player($0) },
            payload: payload
        )
        operations.append(operation)
        return operation
    }

    /// GameCreated, every seat, and (optionally) GameStarted with seat 0 dealing first.
    mutating func setUp(planned: Int = 6, mode: ScoringMode = .scorekeeper, start: Bool = true) {
        add(.gameCreated(.init(config: GameConfig(plannedRounds: planned, scoringMode: mode, tableWord: "Cold Deck"), host: seat(0))))
        for seat in seats {
            add(.playerSeated(.init(seat: seat)))
        }
        if start {
            add(.gameStarted(.init(seatOrder: seats.map(\.id), firstDealer: seat(0))))
        }
    }

    mutating func record(_ hands: [Int], knocker: Int, device: DeviceID? = nil) {
        let number = state.nextRoundNumber
        add(.roundRecorded(.init(round: round(number, hands, knocker: knocker))), device: device)
    }
}

/// Polls a condition on the main actor until it's true or the timeout passes.
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
