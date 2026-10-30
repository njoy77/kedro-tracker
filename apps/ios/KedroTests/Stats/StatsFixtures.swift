import Foundation
@testable import Kedro

/// A person for stats tests.
struct TestPerson: Hashable {
    let ref: PlayerRef
    let name: String

    static func player(_ name: String) -> TestPerson { TestPerson(ref: .player(PlayerID()), name: name) }
    static func guest(_ name: String) -> TestPerson { TestPerson(ref: .guest(GuestID()), name: name) }

    var seat: SeatID { ref.seatID }
}

/// Builds finished games for stats tests, one day apart, oldest first.
struct StatsHistory {
    private(set) var games: [[GameOperation]] = []
    private var startMs: Int64 = 1_767_988_800_000 // 2026-01-09 20:00 UTC

    /// A finished game. `rounds` are hands in the order of `people`, plus the knocker's index.
    @discardableResult
    mutating func game(
        _ people: [TestPerson],
        _ rounds: [([Int], Int)],
        taunts: [(from: Int, to: Int?)] = [],
        abandoned: Bool = false
    ) -> GameID {
        let gameID = GameID()
        let device = DeviceID()
        var builder = OperationBuilder(gameID: gameID, device: device, actor: people[0].ref.playerID, startMs: startMs)
        let seats = people.enumerated().map { order, person in
            Seat(player: person.ref, displayName: person.name, order: order, handle: person.ref.isGuest ? nil : Handle(constant: "p\(order)x"))
        }
        builder.add(.gameCreated(.init(config: GameConfig(plannedRounds: rounds.count, scoringMode: .scorekeeper, tableWord: "Test Table", firstDealerSeat: seats[0].id), host: seats[0].id)))
        for seat in seats { builder.add(.playerSeated(.init(seat: seat))) }
        builder.add(.gameStarted(.init(seatOrder: seats.map(\.id), firstDealer: seats[0].id)))
        var recorded: [Round] = []
        for (offset, row) in rounds.enumerated() {
            let round = Round(number: offset + 1, hands: Dictionary(uniqueKeysWithValues: zip(seats.map(\.id), row.0)), knocker: seats[row.1].id)
            recorded.append(round)
            builder.advance(minutes: 4)
            builder.add(.roundRecorded(.init(round: round)))
        }
        for taunt in taunts {
            let target: TauntTarget = taunt.to.map { .seat(seats[$0].id) } ?? .table
            builder.add(.tauntSent(.init(tauntId: UUID(), roundNumber: 1, from: seats[taunt.from].id, fromName: people[taunt.from].name, target: target, content: .canned(id: "TT-01"))))
        }
        builder.advance(minutes: 1)
        if abandoned {
            builder.add(.gameAbandoned(.init()))
        } else {
            builder.add(.gameFinished(.init(reason: .completed, finalRounds: recorded)))
        }
        games.append(builder.operations)
        startMs += 86_400_000
        return gameID
    }

    /// A quick game where `winnerIndex` wins with 0s and everyone else scores 5 (one round).
    @discardableResult
    mutating func win(_ people: [TestPerson], winner: Int) -> GameID {
        let hands = people.indices.map { $0 == winner ? 0 : 5 }
        return game(people, [(hands, winner)])
    }

    /// Games in a ranked order: `order[0]` finishes first, `order[1]` second, …
    @discardableResult
    mutating func ordered(_ order: [TestPerson]) -> GameID {
        let hands = order.indices.map { $0 * 2 + 1 }
        return game(order, [(hands, 0)])
    }

    var states: [GameState] {
        games.compactMap { operations in operations.first.map { GameState.fold(operations, gameID: $0.gameId) } }
    }

    func snapshot(_ options: StatsOptions = StatsOptions()) -> StatsSnapshot {
        StatsSnapshot.build(states, options: options, calendar: Self.utc)
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }
}

extension PreviewData {
    /// Every demo game folded, plus the finished sample game.
    static var demoStates: [GameState] {
        history.compactMap { operations in operations.first.map { GameState.fold(operations, gameID: $0.gameId) } }
            + [sampleState(throughRound: 8, finished: true)]
    }
}
