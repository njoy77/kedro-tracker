import Foundation
import Testing
@testable import Kedro

@Suite("Sample game (design §17)")
struct SampleGameTests {
    private let state = GameState.fold(PreviewData.sampleOperations(throughRound: 8, finished: true))

    private func total(_ seat: SeatID) -> Int? { state.standing(for: seat)?.total }

    @Test("Final standings: Noah 28, Ana 34, Cleo 65, Ben 67, Sam 70")
    func finals() {
        #expect(state.status == .finished)
        #expect(state.standings.map(\.seat.displayName) == ["Noah", "Ana", "Cleo", "Ben", "Sam"])
        #expect(state.standings.map(\.total) == [28, 34, 65, 67, 70])
        #expect(state.winners == [PreviewData.noahSeat])
        #expect(state.config.plannedRounds == 8)
    }

    @Test("After Round 4 and Round 5")
    func midGame() {
        let afterR4 = PreviewData.sampleState(throughRound: 4)
        #expect(afterR4.totals == [
            PreviewData.noahSeat: 36, PreviewData.anaSeat: 20, PreviewData.benSeat: 38,
            PreviewData.cleoSeat: 34, PreviewData.samSeat: 43,
        ])
        let afterR5 = PreviewData.sampleState(throughRound: 5)
        #expect(afterR5.standings.map(\.total) == [26, 29, 44, 45, 47])
        #expect(afterR5.leaders == [PreviewData.noahSeat])
        #expect(afterR5.progress.currentRound == 6)
        #expect(afterR5.progress.plannedRounds == 6)
        // Noah's last round: landed · −10
        let noah = afterR5.standing(for: PreviewData.noahSeat)
        #expect(noah?.lastRound?.outcome == .landed)
        #expect(noah.flatMap { $0.lastRound.map(Literal.delta) } == "landed · \u{2212}10")
        #expect(afterR5.standing(for: PreviewData.anaSeat).flatMap { $0.lastRound.map(Literal.delta) } == "+9")
    }

    @Test("Knock outcomes: 4 landed, 2 tied, 2 failed")
    func outcomes() {
        let outcomes = state.rounds.compactMap(\.outcome)
        #expect(outcomes == [.landed, .tied, .failed, .failed, .landed, .landed, .tied, .landed])
        #expect(state.rounds[2].scores[PreviewData.noahSeat] == 18) // R3: failed, 8 + 10
        #expect(state.rounds[3].scores[PreviewData.cleoSeat] == 12) // R4: failed, 2 + 10
        #expect(state.rounds[1].scores[PreviewData.benSeat] == 5)   // R2: tied with Cleo
    }

    @Test("Dealers R1–R8: Noah, Ana, Ben, Cleo, Sam, Noah, Ana, Ben")
    func dealers() {
        let names = (1...8).compactMap { state.dealer(forRound: $0) }.map { state.name(of: $0) }
        #expect(names == ["Noah", "Ana", "Ben", "Cleo", "Sam", "Noah", "Ana", "Ben"])
        #expect(PreviewData.sampleState(throughRound: 5).currentDealer == PreviewData.noahSeat)
        #expect(state.currentDealer == nil) // finished
    }

    @Test("The extension to 8 rounds is on the record")
    func extensionLogged() {
        let changes = state.audit.compactMap { entry -> Change<Int>? in
            if case .plannedRoundsChanged(let change) = entry.change { change } else { nil }
        }
        #expect(changes == [Change(before: 6, after: 8)])
        #expect(state.audit.contains { $0.summary == "Noah added 2 rounds. Now playing to 8" })
    }

    @Test("Folding is independent of arrival order")
    func orderIndependent() {
        var generator = SeededGenerator(seed: 42)
        let operations = PreviewData.sampleOperations(throughRound: 8, finished: true)
        for _ in 0..<5 {
            #expect(GameState.fold(operations.shuffled(using: &generator)) == state)
        }
    }

    @Test("Generated history: 40 finished games, 1 abandoned, Ben 4 games, Sam 2")
    func history() {
        let states = PreviewData.history.map { GameState.fold($0) }
        #expect(states.count == 41)
        let finished = states.filter { $0.status == .finished }
        #expect(finished.count == 40)
        #expect(states.filter { $0.status == .abandoned }.count == 1)
        #expect(finished.filter { $0.seat(PreviewData.benSeat) != nil }.count == Ratings.rankedAfterGames - 1)
        #expect(finished.filter { $0.seat(PreviewData.samSeat) != nil }.count == 2)
        let names = Set(finished.flatMap(\.seats).map(\.displayName))
        #expect(names.isSuperset(of: ["Priya", "Jo", "Max", "Maya", "Theo", "Leo"]))
        #expect(finished.contains { $0.seats.count == 8 })
        // Every history game happens before the sample game.
        #expect(states.allSatisfy { ($0.createdAt ?? .distantFuture) < Date(timeIntervalSince1970: TimeInterval(PreviewData.sampleStartMs) / 1000) })
        // All operation IDs are unique.
        let ids = PreviewData.historyOperations.map(\.opId) + PreviewData.sampleOperations().map(\.opId)
        #expect(Set(ids).count == ids.count)
    }
}
