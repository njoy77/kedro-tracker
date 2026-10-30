import Foundation

/// Extra preview games for the Table's own previews (8 players, self-report, a fresh table). The
/// §17 sample game lives in `PreviewData`.
nonisolated enum TablePreviews {
    static let eightGameID = GameID(PreviewData.fixedUUID(kind: 4, 80))
    static let selfReportGameID = GameID(PreviewData.fixedUUID(kind: 4, 81))

    static var eightSeats: [Seat] {
        let people = [PreviewData.noah, PreviewData.ana, PreviewData.ben, PreviewData.cleo,
                      PreviewData.priya, PreviewData.jo, PreviewData.max, PreviewData.maya]
        return people.enumerated().map { index, person in
            Seat(person, order: index, deviceID: index == 0 ? PreviewData.noahPhone : nil, languageLevel: .unhinged)
        }
    }

    static func eightPlayerOperations(rounds: Int = 4) -> [GameOperation] {
        let seats = eightSeats
        var builder = OperationBuilder(gameID: eightGameID, device: PreviewData.noahPhone, actor: PreviewData.noah.id, startMs: PreviewData.sampleStartMs)
        builder.add(.gameCreated(.init(config: GameConfig(plannedRounds: 8, tableWord: "Last Call", firstDealerSeat: seats[0].id, scorekeeperSeat: seats[0].id), host: seats[0].id)))
        for seat in seats { builder.add(.playerSeated(.init(seat: seat))) }
        builder.add(.gameStarted(.init(seatOrder: seats.map(\.id), firstDealer: seats[0].id)))
        let table: [(Int, [Int])] = [
            (1, [9, 3, 12, 7, 15, 6, 8, 10]),
            (4, [6, 11, 5, 5, 2, 9, 14, 7]),
            (0, [4, 3, 14, 10, 9, 8, 6, 12]),
            (6, [3, 16, 7, 2, -1, 11, 1, 5]),
        ]
        for (number, row) in table.prefix(rounds).enumerated() {
            builder.advance(minutes: 4)
            let hands = Dictionary(uniqueKeysWithValues: zip(seats.map(\.id), row.1))
            builder.add(.roundRecorded(.init(round: Round(number: number + 1, hands: hands, knocker: seats[row.0].id))))
        }
        return builder.operations
    }

    static var eightPlayerState: GameState { GameState.fold(eightPlayerOperations(), gameID: eightGameID) }

    /// The sample seats in self-report mode, with some hands reported for Round 3.
    static func selfReportOperations(reported: Int = 3, claims: [Int] = [1]) -> [GameOperation] {
        let seats = PreviewData.sampleSeats
        var builder = OperationBuilder(gameID: selfReportGameID, device: PreviewData.noahPhone, actor: PreviewData.noah.id, startMs: PreviewData.sampleStartMs)
        builder.add(.gameCreated(.init(config: GameConfig(plannedRounds: 6, scoringMode: .selfReport, tableWord: "Dead Hand", firstDealerSeat: seats[0].id), host: seats[0].id)))
        for seat in seats { builder.add(.playerSeated(.init(seat: seat))) }
        builder.add(.gameStarted(.init(seatOrder: seats.map(\.id), firstDealer: seats[0].id)))
        for round in PreviewData.sampleRounds.prefix(2) {
            builder.advance(minutes: 4)
            builder.add(.roundRecorded(.init(round: round)))
        }
        builder.advance(minutes: 3)
        let hands = [5, 2, 9, 8, 1]
        for (index, seat) in seats.prefix(reported).enumerated() {
            builder.add(.handReported(.init(roundNumber: 3, seatId: seat.id, hand: hands[index], knocked: claims.contains(index))))
        }
        return builder.operations
    }

    @MainActor
    static func session(_ operations: [GameOperation], gameID: GameID) -> GameSession {
        GameSession(
            gameID: gameID,
            operations: operations,
            store: InMemoryGameStore(operations: operations),
            transport: LocalOnlyTransport(),
            identity: PreviewData.noahIdentity,
            clock: HybridLogicalClock(device: PreviewData.noahPhone)
        )
    }

    @MainActor
    static var eightPlayerSession: GameSession { session(eightPlayerOperations(), gameID: eightGameID) }

    @MainActor
    static func selfReportSession(reported: Int = 3, claims: [Int] = [1]) -> GameSession {
        session(selfReportOperations(reported: reported, claims: claims), gameID: selfReportGameID)
    }

    /// A fresh table: dealt, no rounds yet.
    @MainActor
    static var freshSession: GameSession {
        session(PreviewData.sampleOperations(throughRound: 0, finished: false), gameID: PreviewData.sampleGameID)
    }
}
