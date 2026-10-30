import Foundation
import Testing
@testable import Kedro

@Suite("GameSession")
struct GameSessionTests {
    private func makeSession(throughRound: Int = 5) -> (GameSession, InMemoryGameStore, LocalOnlyTransport) {
        let operations = PreviewData.sampleOperations(throughRound: throughRound, finished: false)
        let store = InMemoryGameStore(operations: operations)
        let transport = LocalOnlyTransport()
        let session = GameSession(
            gameID: PreviewData.sampleGameID, operations: operations, store: store, transport: transport,
            identity: PreviewData.noahIdentity, clock: HybridLogicalClock(device: PreviewData.noahPhone)
        )
        return (session, store, transport)
    }

    @Test("Recording a round updates state, the store and the transport")
    func record() async throws {
        let (session, store, transport) = makeSession()
        #expect(session.isScorekeeper)
        let round = PreviewData.sampleRounds[5]
        try await session.recordRound(hands: round.hands, knocker: round.knocker)
        #expect(session.state.rounds.count == 6)
        #expect(session.state.standings.map(\.total) == [31, 33, 53, 53, 37].sorted()) // Ana 31, Noah 33, Sam 37, Ben 53, Cleo 53
        #expect(session.state.standings.first?.seat.displayName == "Ana")
        #expect(transport.sent.count == 1)
        #expect(try await store.operations(for: PreviewData.sampleGameID).count == session.operations.count)
        #expect(session.state.currentDealer == PreviewData.anaSeat)
    }

    @Test("Invalid rounds and locked games throw")
    func guards() async throws {
        let (session, _, _) = makeSession()
        await #expect(throws: GameSession.SessionError.invalidRound) {
            try await session.recordRound(hands: [PreviewData.noahSeat: 3], knocker: PreviewData.noahSeat)
        }
        try await session.finish()
        #expect(session.state.status == .finished)
        #expect(session.state.finishReason == .endedEarly)
        await #expect(throws: GameSession.SessionError.gameLocked) {
            try await session.undoLastRound()
        }
    }

    @Test("Undo the last round moves the deal back")
    func undoLast() async throws {
        let (session, _, _) = makeSession()
        let dealer = session.state.currentDealer
        let round = PreviewData.sampleRounds[5]
        try await session.recordRound(hands: round.hands, knocker: round.knocker)
        try await session.undoLastRound()
        #expect(session.state.rounds.count == 5)
        #expect(session.state.currentDealer == dealer)
    }

    @Test("The author can undo their own edit")
    func undoEdit() async throws {
        let (session, _, _) = makeSession()
        var hands = PreviewData.sampleRounds[3].hands
        hands[PreviewData.samSeat] = 5 // Cleo's 2 is now strictly lowest
        try await session.editRound(4, hands: hands, knocker: PreviewData.cleoSeat)
        #expect(session.state.round(4)?.outcome == .landed)
        let entry = try #require(session.state.audit.last)
        #expect(session.canUndo(entry))
        try await session.undo(entry)
        #expect(session.state.round(4)?.round == PreviewData.sampleRounds[3])
    }

    @Test("Preview doesn't change the game")
    func preview() {
        let (session, _, _) = makeSession()
        var hands = PreviewData.sampleRounds[0].hands
        hands[PreviewData.noahSeat] = 1
        let preview = session.preview(.roundEdited(.init(round: Round(number: 1, hands: hands, knocker: PreviewData.anaSeat))))
        #expect(preview.round(1)?.outcome == .failed) // Ana knocked on 3; Noah had 1
        #expect(session.state.round(1)?.outcome == .landed)
        #expect(session.operations.count == PreviewData.sampleOperations(throughRound: 5, finished: false).count)
    }

    @Test("Operations from other phones are stored and folded in")
    func incoming() async throws {
        let (session, store, transport) = makeSession()
        let task = Task { await session.run() }
        defer { task.cancel() }
        // Ana's phone records Round 6.
        let all = PreviewData.sampleOperations(throughRound: 6, finished: false)
        let known = Set(session.operations.map(\.opId))
        let fromAna = all.filter { !known.contains($0.opId) }
        #expect(!fromAna.isEmpty)
        // Deliver until it lands: run() subscribes to the transport asynchronously, and a batch
        // sent before that is dropped. Redelivering is harmless (the store de-dupes by opId).
        #expect(await eventually(timeout: .seconds(10)) {
            if session.state.rounds.count == 6 { return true }
            transport.deliver(fromAna)
            return false
        })
        #expect(try await store.operations(for: PreviewData.sampleGameID).count == all.count)
    }

    @Test("Creating a game seats the host and Deal starts it")
    func create() async throws {
        let store = InMemoryGameStore()
        let transport = LocalOnlyTransport()
        let host = PreviewData.noahProfile.seat(order: 0, device: PreviewData.noahPhone, languageLevel: .unhinged, gamesPlayed: 40)
        let others = [Seat(PreviewData.ana, order: 1), Seat(player: .guest(GuestID()), displayName: "Sam", order: 2)]
        let session = try await GameSession.create(
            config: GameConfig(plannedRounds: 5, tableWord: "Last Call"), host: host, others: others,
            store: store, transport: transport, identity: PreviewData.noahIdentity, clock: HybridLogicalClock(device: PreviewData.noahPhone)
        )
        #expect(session.state.status == .lobby)
        #expect(session.state.seats.map(\.displayName) == ["Noah", "Ana", "Sam"])
        try await session.start()
        #expect(session.state.status == .active)
        #expect(session.state.currentDealer == host.id)
        #expect(session.mySeatID == host.id)
        #expect(try await store.games().count == 1)
    }
}

@Suite("ToastCenter")
struct ToastCenterTests {
    @Test("At most three on screen; older ones collapse into the overflow")
    func maxThree() {
        let center = ToastCenter()
        for index in 0..<5 {
            center.show(Toast(message: "\(index)", duration: .seconds(60)))
        }
        #expect(center.visible.map(\.message) == ["2", "3", "4"])
        #expect(center.overflowCount == 2)
        center.dismissAll()
        #expect(center.visible.isEmpty)
        #expect(center.overflowCount == 0)
    }

    @Test("Toasts wait while the Round sheet is open")
    func deferring() {
        let center = ToastCenter()
        center.isDeferring = true
        center.show(Toast(kind: .taunt, message: "a", duration: .seconds(60)))
        center.show(Toast(kind: .liveKnock, message: "b", duration: .seconds(60)))
        #expect(center.visible.isEmpty)
        #expect(center.deferred.count == 2)
        center.isDeferring = false
        #expect(center.visible.map(\.message) == ["a", "b"])
        #expect(center.deferred.isEmpty)
    }

    @Test("Actions run and dismiss")
    func actions() {
        let center = ToastCenter()
        var undone = false
        center.show(Toast(message: "Round 6 saved.", action: .init(title: "Undo") { undone = true }, duration: .seconds(60)))
        let id = try? #require(center.visible.first?.id)
        if let id { center.performAction(of: id) }
        #expect(undone)
        #expect(center.visible.isEmpty)
    }

    @Test("Toasts leave on their own")
    func autoDismiss() async {
        let center = ToastCenter()
        center.show(Toast(message: "bye", duration: .milliseconds(30)))
        #expect(await eventually { center.visible.isEmpty })
    }
}
