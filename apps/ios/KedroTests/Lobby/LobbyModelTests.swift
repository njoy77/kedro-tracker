import Foundation
import Testing
@testable import Kedro

@Suite("Lobby model")
@MainActor
struct LobbyModelTests {
    private func makeApp() -> AppModel {
        let defaults = UserDefaults(suiteName: "kedro.tests.lobby.\(UUID().uuidString)") ?? .standard
        return AppModel(
            store: InMemoryGameStore(operations: PreviewData.historyOperations),
            preferences: AppPreferences(defaults: defaults),
            profiles: ProfileStore(container: nil, profile: PreviewData.noahProfile),
            deviceID: PreviewData.noahPhone
        )
    }

    @Test("A fresh lobby is a draft with the host seated, and can't deal alone")
    func fresh() async throws {
        let app = makeApp()
        let lobby = try LobbyModel(app: app)
        #expect(!lobby.isOpen)
        #expect(lobby.seats.map(\.displayName) == ["Noah"])
        #expect(lobby.issues.first == .tooFewSeats)
        #expect(!lobby.canDeal)
        await #expect(throws: LobbyModel.LobbyError.cantDeal) { try await lobby.deal() }
        #expect(try await app.store.games().allSatisfy { $0.status != .lobby && $0.status != .active })
    }

    @Test("No profile, no lobby")
    func noProfile() {
        let app = AppModel(store: InMemoryGameStore(), profiles: ProfileStore(container: nil))
        #expect(throws: LobbyModel.LobbyError.noProfile) { try LobbyModel(app: app) }
    }

    @Test("Adding, removing and dealing makes an active game with the lobby's seats and settings")
    func deal() async throws {
        let app = makeApp()
        let lobby = try LobbyModel(app: app)
        await lobby.add(PreviewData.ana)
        await lobby.add(PreviewData.ben)
        await lobby.add(Seat(player: .guest(PreviewData.samID), displayName: "Sam", order: 0))
        await lobby.add(PreviewData.ana) // already seated: ignored
        #expect(lobby.seats.map(\.displayName) == ["Noah", "Ana", "Ben", "Sam"])
        await lobby.remove(PreviewData.benSeat)
        await lobby.remove(lobby.hostSeatID) // the host stays
        #expect(lobby.seats.map(\.displayName) == ["Noah", "Ana", "Sam"])

        await lobby.setPlannedRounds(8)
        lobby.firstDealer = PreviewData.anaSeat
        #expect(lobby.canDeal)
        try await lobby.deal()

        let session = try #require(app.liveGame)
        #expect(session.state.status == .active)
        #expect(session.state.seats.map(\.displayName) == ["Noah", "Ana", "Sam"])
        #expect(session.state.config.plannedRounds == 8)
        #expect(session.state.currentDealer == PreviewData.anaSeat)
        #expect(app.preferences.lastPlannedRounds == 8)
    }

    @Test("Reordering before Deal sets the clockwise order")
    func reorder() async throws {
        let app = makeApp()
        let lobby = try LobbyModel(app: app)
        for player in [PreviewData.ana, PreviewData.ben, PreviewData.cleo] { await lobby.add(player) }
        await lobby.move(from: IndexSet(integer: 0), to: 4) // the host to the end
        #expect(lobby.seats.map(\.displayName) == ["Ana", "Ben", "Cleo", "Noah"])
        try await lobby.deal()
        let session = try #require(app.liveGame)
        #expect(session.state.seats.map(\.displayName) == ["Ana", "Ben", "Cleo", "Noah"])
        // First deal defaults to the host.
        #expect(session.state.currentDealer == PreviewData.noahSeat)
    }

    @Test("Self-report gives guests the host as reporter")
    func selfReport() async throws {
        let app = makeApp()
        let lobby = try LobbyModel(app: app)
        await lobby.add(Seat(player: .guest(PreviewData.samID), displayName: "Sam", order: 0))
        await lobby.setScoringMode(.selfReport)
        #expect(lobby.seats.last?.reporter == lobby.hostSeatID)
        await lobby.add(Seat(player: .guest(GuestID()), displayName: "Leo", order: 0))
        #expect(lobby.seats.last?.reporter == lobby.hostSeatID)
        await lobby.add(PreviewData.ana)
        #expect(lobby.canDeal)
    }

    @Test("Changing the table word after opening reopens the table with the same seats")
    func reopen() async throws {
        let app = makeApp()
        let lobby = try LobbyModel(app: app)
        await lobby.add(PreviewData.ana)
        await lobby.add(PreviewData.ben)
        let first = try await lobby.open()
        #expect(lobby.isOpen)
        #expect(lobby.inviteToken?.gameID == first.gameID)
        let word = lobby.config.tableWord

        await lobby.regenerateTableWord()
        let second = try #require(app.liveGame)
        #expect(second.gameID != first.gameID)
        #expect(second.state.config.tableWord != word)
        #expect(second.state.seats.map(\.displayName) == ["Noah", "Ana", "Ben"])
        #expect(first.state.status == .abandoned)
        #expect(lobby.canChangeTableShape)
    }

    @Test("Once another phone sits down, the table shape locks")
    func locksWhenSomeoneSits() async throws {
        let app = makeApp()
        let lobby = try LobbyModel(app: app)
        await lobby.add(PreviewData.ana)
        let session = try await lobby.open()
        var anaSeat = try #require(session.state.seat(PreviewData.anaSeat))
        anaSeat.deviceID = PreviewData.anaPhone
        try await session.send(.playerSeated(.init(seat: anaSeat)))
        #expect(lobby.otherPhonesSeated)
        #expect(!lobby.canChangeTableShape)
        let word = lobby.config.tableWord
        await lobby.regenerateTableWord()
        #expect(lobby.config.tableWord == word)
        #expect(app.liveGame?.gameID == session.gameID)
    }

    @Test("Cancel abandons an open lobby and leaves it")
    func cancel() async throws {
        let app = makeApp()
        let lobby = try LobbyModel(app: app)
        await lobby.add(PreviewData.ana)
        let session = try await lobby.open()
        await lobby.cancel()
        #expect(app.liveGame == nil)
        #expect(session.state.status == .abandoned)
        #expect(!lobby.isOpen)
    }

    @Test("Run It Back keeps the people and rounds and rotates the first deal")
    func rematch() throws {
        let app = makeApp()
        let previous = PreviewData.sampleState(throughRound: 8, finished: true)
        let lobby = try LobbyModel(app: app, rematchOf: previous)
        #expect(lobby.seats.map(\.displayName) == previous.seats.map(\.displayName))
        #expect(lobby.seats.allSatisfy { $0.id == lobby.hostSeatID || $0.deviceID == nil })
        #expect(lobby.plannedRounds == previous.config.plannedRounds)
        #expect(lobby.firstDealer == PreviewData.anaSeat) // Noah dealt first last time
        #expect(lobby.canDeal)
    }
}
