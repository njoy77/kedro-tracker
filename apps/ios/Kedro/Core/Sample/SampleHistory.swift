import Foundation

/// A deterministic random generator (SplitMix64) so sample data is identical on every run.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension PreviewData {
    /// A generated history for stats screens: 40 finished games (plus one abandoned) among the
    /// ten sample players and Sam (guest), January to October 2026, all before the sample game.
    ///
    /// Shaped to match the sample story where it matters: Ben has exactly 4 games (the sample
    /// game is his 5th, his debut), Sam has exactly 2 (the sample game is his 3rd), Noah plays
    /// almost every game, and Ana is a little sharper than everyone else.
    nonisolated static let history: [[GameOperation]] = makeHistory()

    /// All history operations, flattened.
    nonisolated static var historyOperations: [GameOperation] { history.flatMap { $0 } }

    private nonisolated static func makeHistory(seed: UInt64 = 0xC0FF_EE15_CA4B_1000, games: Int = 40) -> [[GameOperation]] {
        var random = SeededGenerator(seed: seed)
        // Average hand per player: lower is better.
        let skill: [PlayerID: Int] = [
            noah.id: 7, ana.id: 6, ben.id: 9, cleo.id: 8, priya.id: 7,
            jo.id: 9, max.id: 8, maya.id: 7, theo.id: 9, leo.id: 10,
        ]
        let regulars = [ana, cleo, priya, jo, max, maya, theo, leo]
        var benGamesLeft = 4
        var samGamesLeft = 2
        var gamesPlayed: [SeatID: Int] = [:]
        var result: [[GameOperation]] = []
        // 2026-01-09 20:00 UTC, one game every 4–6 days (all before the sample game on 2026-10-24).
        var startMs: Int64 = 1_767_988_800_000

        for index in 0..<(games + 1) {
            let isAbandoned = index == 17
            var people: [PlayerSummary] = []
            if index % 7 != 3 { people.append(noah) }
            let size = index == 25 ? 8 : Int.random(in: 3...6, using: &random)
            var pool = regulars.shuffled(using: &random)
            if benGamesLeft > 0, index % 9 == 2 || games - index <= benGamesLeft * 2 {
                pool.insert(ben, at: 0)
                benGamesLeft -= 1
            }
            let includeSam = samGamesLeft > 0 && (index == 30 || index == 36)
            if includeSam { samGamesLeft -= 1 }
            while people.count < size - (includeSam ? 1 : 0), let next = pool.first {
                pool.removeFirst()
                if !people.contains(where: { $0.id == next.id }) { people.append(next) }
            }

            var seats = people.enumerated().map { order, player in
                var seat = Seat(player, order: order, languageLevel: .unhinged)
                seat.gamesPlayed = gamesPlayed[player.seatID, default: 0]
                return seat
            }
            if includeSam {
                seats.append(Seat(player: .guest(samID), displayName: "Sam", order: seats.count, gamesPlayed: gamesPlayed[samSeat, default: 0]))
            }

            let gameID = GameID(fixedUUID(kind: 6, UInt8(index + 1)))
            let host = people[0]
            let device = DeviceID(fixedUUID(kind: 7, UInt8(index % 10 + 1)))
            var builder = OperationBuilder(gameID: gameID, device: device, actor: host.id, startMs: startMs)
            let planned = [5, 6, 6, 8, 8, 10].randomElement(using: &random) ?? 6
            let word = TableWord.random(using: &random)
            builder.add(.gameCreated(.init(config: GameConfig(plannedRounds: planned, scoringMode: .scorekeeper, tableWord: word, firstDealerSeat: host.seatID), host: host.seatID)))
            for seat in seats {
                builder.add(.playerSeated(.init(seat: seat)))
            }
            builder.add(.gameStarted(.init(seatOrder: seats.map(\.id), firstDealer: seats[index % seats.count].id)))

            var rounds: [Round] = []
            let roundsToPlay = isAbandoned ? 3 : planned
            for number in 1...roundsToPlay {
                var hands: [SeatID: Int] = [:]
                for seat in seats {
                    let mean = seat.player.playerID.flatMap { skill[$0] } ?? 9
                    var hand = Int.random(in: 0...(mean * 2), using: &random)
                    if Int.random(in: 0..<14, using: &random) == 0 { hand = -1 }
                    if Int.random(in: 0..<60, using: &random) == 0 { hand = Int.random(in: 30...44, using: &random) }
                    hands[seat.id] = hand
                }
                // Knockers are usually low; sometimes they get greedy.
                let byHand = seats.map(\.id).sorted { (hands[$0] ?? 0, $0) < (hands[$1] ?? 0, $1) }
                let knocker = Int.random(in: 0..<10, using: &random) < 7
                    ? byHand[Int.random(in: 0..<min(2, byHand.count), using: &random)]
                    : byHand.randomElement(using: &random) ?? byHand[0]
                let round = Round(number: number, hands: hands, knocker: knocker)
                rounds.append(round)
                builder.advance(minutes: Double(Int.random(in: 3...6, using: &random)))
                builder.add(.roundRecorded(.init(round: round)))
            }
            builder.advance(minutes: 1)
            if isAbandoned {
                builder.add(.gameAbandoned(.init()))
            } else {
                builder.add(.gameFinished(.init(reason: .completed, finalRounds: rounds)))
                for seat in seats { gamesPlayed[seat.id, default: 0] += 1 }
            }
            result.append(builder.operations)
            startMs += Int64(Int.random(in: 4...6, using: &random)) * 86_400_000
        }
        return result
    }
}
