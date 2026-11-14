import Foundation
import Testing
@testable import Kedro

/// The 🐴 neigh: the `Neighed` op, lossy op pages, the fold's counts, the live neigh rule, the
/// `?features=neighs` query and the neigh stats.
@Suite("Neighs")
struct NeighTests {
    private static let gameID = "8f14e45f-ceea-467f-a9b0-3a1c4b2d5e6f"

    /// One op as the API sends it.
    private static func opJSON(type: String, payload: String, wallMs: Int64 = 1, opID: UUID = UUID()) -> String {
        #"{"opId":"\#(opID.uuidString.lowercased())","gameId":"\#(gameID)","deviceId":"\#(gameID)","hlc":{"wallMs":\#(wallMs),"counter":0,"node":"n"},"actorPlayerId":null,"type":"\#(type)","payload":\#(payload)}"#
    }

    private func started() -> TestGame {
        var game = TestGame(players: 3)
        game.setUp()
        return game
    }

    // MARK: Op model

    @Test("Neighed decodes from the API's JSON, with and without a round number")
    func decodeNeighed() throws {
        let seat = PreviewData.samSeat
        let decoder = KedroJSON.decoder()
        let withRound = try decoder.decode(GameOperation.self, from: Data(Self.opJSON(type: "Neighed", payload: #"{"seatId":"\#(seat.rawValue)","roundNumber":6}"#).utf8))
        #expect(withRound.type == .neighed)
        #expect(withRound.payload == .neighed(.init(seatId: seat, roundNumber: 6)))

        let noRound = try decoder.decode(GameOperation.self, from: Data(Self.opJSON(type: "Neighed", payload: #"{"seatId":"\#(seat.rawValue)"}"#).utf8))
        #expect(noRound.payload == .neighed(.init(seatId: seat, roundNumber: nil)))

        let encoded = try #require(String(data: KedroJSON.encoder().encode(withRound), encoding: .utf8))
        #expect(encoded.contains(#""type":"Neighed""#))
        #expect(encoded.contains(#""payload":{"roundNumber":6,"seatId":"\#(seat.rawValue)"}"#))
    }

    @Test("Neighed is not state-changing and is allowed after a finish (packages/shared)")
    func classification() {
        #expect(!OperationType.neighed.isStateChanging)
        // packages/shared `NON_STATE_CHANGING` and `ALLOWED_AFTER_FINISH`.
        let nonStateChanging: Set<OperationType> = [.tauntSent, .tauntRetracted, .reactionAdded, .receiptSent, .tableSpeakerClaimed, .neighed]
        let allowedAfterFinish: Set<OperationType> = [.receiptSent, .reactionAdded, .tableSpeakerClaimed, .tauntRetracted, .neighed]
        #expect(Set(OperationType.allCases.filter { !$0.isStateChanging }) == nonStateChanging)
        #expect(Set(OperationType.allCases.filter(\.isAllowedAfterFinish)) == allowedAfterFinish)
    }

    // MARK: Lossy pages

    @Test("An op page skips op types this build doesn't know, but still counts them for paging")
    func lossyPage() throws {
        let known = Self.opJSON(type: "Neighed", payload: #"{"seatId":"\#(PreviewData.samSeat.rawValue)"}"#, wallMs: 10)
        let unknown = Self.opJSON(type: "SomethingFromTheFuture", payload: #"{"whatever":[1,2,3]}"#, wallMs: 20)
        let json = #"{"ops":[\#(known),\#(unknown)]}"#
        let page = try KedroJSON.decoder().decode(OpsPage.self, from: Data(json.utf8))
        #expect(page.ops.map(\.type) == [.neighed])
        #expect(page.receivedCount == 2)
        #expect(page.lastHLC?.wallMs == 20, "the cursor moves past skipped ops")
    }

    @Test("A malformed op of a known type still fails the page")
    func malformedKnownOp() {
        let broken = Self.opJSON(type: "Neighed", payload: #"{"roundNumber":2}"#)
        #expect(throws: DecodingError.self) {
            try KedroJSON.decoder().decode(OpsPage.self, from: Data(#"{"ops":[\#(broken)]}"#.utf8))
        }
    }

    // MARK: Fold

    @Test("The fold counts neighs per seat, during and after the game, without touching scores")
    func foldCounts() throws {
        var game = started()
        game.add(.neighed(.init(seatId: game.seat(1), roundNumber: 1)))
        game.record([2, 9, 20], knocker: 0)
        let before = game.state
        game.add(.neighed(.init(seatId: game.seat(1), roundNumber: 2)), device: game.deviceB)
        game.add(.neighed(.init(seatId: game.seat(2), roundNumber: 2)))
        let during = game.state
        #expect(during.neighCount(for: game.seat(1)) == 2)
        #expect(during.neighCount(for: game.seat(2)) == 1)
        #expect(during.neighCount(for: game.seat(0)) == 0)
        #expect(during.neighCounts == [game.seat(1): 2, game.seat(2): 1])
        #expect(during.standings == before.standings)
        #expect(during.audit == before.audit)

        game.add(.gameFinished(.init(reason: .endedEarly, finalRounds: during.rounds.map(\.round))))
        game.add(.neighed(.init(seatId: game.seat(0), roundNumber: nil)))
        let finished = game.state
        #expect(finished.status == .finished)
        #expect(finished.neighCount(for: game.seat(0)) == 1, "kept after the finish")
        #expect(finished.lateOperations.isEmpty)
    }

    @Test("An abandoned game ignores neighs")
    func abandoned() {
        var game = started()
        game.add(.gameAbandoned(.init()))
        game.add(.neighed(.init(seatId: game.seat(1), roundNumber: 1)))
        #expect(game.state.neighs.isEmpty)
    }

    @Test("GameSession.neigh sends the round in play")
    func sessionNeigh() async throws {
        let session = PreviewData.sampleSession(throughRound: 5)
        let before = session.state.neighCount(for: PreviewData.anaSeat)
        let operation = try await session.neigh(PreviewData.anaSeat)
        #expect(operation.payload == .neighed(.init(seatId: PreviewData.anaSeat, roundNumber: 6)))
        #expect(session.state.neighCount(for: PreviewData.anaSeat) == before + 1)
    }

    // MARK: Live neigh

    private func listener(_ game: TestGame, device: DeviceID) -> SoundListener {
        SoundListener(
            device: device, seat: nil, isTableSpeaker: false, learners: [],
            deviceForOperation: Dictionary(game.operations.map { ($0.opId, $0.deviceId) }, uniquingKeysWith: { first, _ in first })
        )
    }

    @Test("A live neigh from another phone neighs on every phone, table speaker or not")
    func liveNeigh() {
        var game = started()
        let before = game.state
        let op = game.add(.neighed(.init(seatId: game.seat(1), roundNumber: 1)), device: game.deviceB)
        let after = game.state
        let now = op.hlc.date.addingTimeInterval(1)
        #expect(SoundCues.playsNeigh(from: before, to: after, listener: listener(game, device: game.deviceA), now: now))
        // The tapping phone played it on the tap already.
        #expect(!SoundCues.playsNeigh(from: before, to: after, listener: listener(game, device: game.deviceB), now: now))
        // Nothing new: silent.
        #expect(!SoundCues.playsNeigh(from: after, to: after, listener: listener(game, device: game.deviceA), now: now))
    }

    @Test("Old neighs from a backfill or catch-up stay quiet")
    func catchUpIsQuiet() {
        var game = started()
        let before = game.state
        let op = game.add(.neighed(.init(seatId: game.seat(1), roundNumber: 1)), device: game.deviceB)
        let after = game.state
        let later = op.hlc.date.addingTimeInterval(SoundCues.liveNeighWindow + 60)
        #expect(!SoundCues.playsNeigh(from: before, to: after, listener: listener(game, device: game.deviceA), now: later))
    }

    @Test("The neigh plays even with the app's sounds off")
    func neighIgnoresSettings() {
        let defaults = UserDefaults(suiteName: "neigh-\(UUID().uuidString)") ?? .standard
        let settings = SoundSettings(defaults: defaults)
        #expect(!settings.isEnabled)
        let player = RecordingSoundPlayer()
        player.play(.winner, settings: settings)
        player.neigh()
        #expect(player.played.isEmpty)
        #expect(player.neighs == 1)
    }

    // MARK: Features query

    @Test("Every ops read asks for ?features=neighs")
    func featuresQuery() async throws {
        let http = MockHTTP { _ in (200, MockHTTP.json(OpsPage(ops: []))) }
        let api = APIClient.mock(http)
        let game = GameID()
        _ = try await api.operations(for: game)
        _ = try await api.operations(for: game, after: HLC(wallMs: 5, counter: 0, node: "n"))
        let gets = http.requests.filter { $0.method == "GET" }
        #expect(gets.count == 2)
        #expect(gets.allSatisfy { $0.path == "/v1/games/\(game.uuidString)/ops" })
        #expect(gets.allSatisfy { $0.query["features"] == "neighs" })
        #expect(gets.last?.query["after"] != nil)
    }

    @Test("A pull stores the ops it knows and skips the rest")
    func pullSkipsUnknown() async throws {
        var remote = started()
        remote.add(.neighed(.init(seatId: remote.seat(1), roundNumber: 1)), device: remote.deviceB)
        let known = try String(decoding: KedroJSON.encoder().encode(OpsPage(ops: remote.operations)), as: UTF8.self)
        // Splice an op of a future type into the page.
        let future = Self.opJSON(type: "FutureThing", payload: "{}", wallMs: remote.wallMs + 1)
            .replacingOccurrences(of: Self.gameID, with: remote.gameID.uuidString.lowercased())
        let body = known.replacingOccurrences(of: "]}", with: ",\(future)]}", options: .backwards, range: known.range(of: "]}", options: .backwards))
        let http = MockHTTP { request in
            request.method == "GET" ? (200, Data(body.utf8)) : (200, MockHTTP.json(OpsUploadResult(accepted: [], duplicates: [])))
        }
        let store = InMemoryGameStore()
        let sync = BackendSync(api: .mock(http), store: store, storage: InMemorySyncQueueStorage(), feed: SilentOpsFeed())
        await sync.pull(remote.gameID, full: true)
        let stored = try await store.operations(for: remote.gameID)
        #expect(Set(stored.map(\.opId)) == Set(remote.operations.map(\.opId)))
        #expect(GameState.fold(stored).neighCount(for: remote.seat(1)) == 1)
    }

    // MARK: Stats

    @Test("Counted games add up each person's neighs, and the Most Neighs record")
    func localStats() throws {
        var game = started()
        game.add(.neighed(.init(seatId: game.seat(1), roundNumber: 1)))
        game.add(.neighed(.init(seatId: game.seat(1), roundNumber: 1)))
        game.add(.neighed(.init(seatId: game.seat(2), roundNumber: 1)))
        game.record([2, 9, 20], knocker: 0)
        game.add(.gameFinished(.init(reason: .endedEarly, finalRounds: game.state.rounds.map(\.round))))
        var options = StatsOptions()
        options.minimumRounds = 1
        let snapshot = StatsSnapshot.build([game.state], options: options)
        let p1 = try #require(snapshot.record(game.seats[1].player))
        #expect(p1.neighs == 2)
        #expect(p1.neighsPerGame == 2)
        #expect(snapshot.record(game.seats[0].player)?.neighs == 0)
        let records = snapshot.records(.mostNeighs, scope: .global, viewer: nil)
        #expect(records.map(\.value) == [2, 1])
        #expect(records.first?.ref == game.seats[1].player)
    }

    @Test("Server rows decode neighs, and read 0 when an older server leaves them out")
    func serverRows() throws {
        let ana = PreviewData.ana
        let player = #"{"id":"\#(ana.id.uuidString.lowercased())","displayName":"Ana","handle":"\#(ana.handle.rawValue)","avatar":{"kind":"curated","id":"spade"}}"#
        func row(_ extra: String) -> String {
            #"{"rank":1,"player":\#(player),"value":1100,"rating":1100,"gamesPlayed":12,"wins":5,"winRate":0.42,"avgScore":14.5,"knocks":9,"knocksLanded":4,"knockSuccess":0.44,\#(extra)"isMe":false}"#
        }
        let json = #"{"scope":"global","sort":"rating","rows":[\#(row(#""neighs":18,"neighsPerGame":1.5,"#)),\#(row(""))],"notYetRanked":[],"notYetRankedCount":0}"#
        let response = try KedroJSON.decoder().decode(LeaderboardResponse.self, from: Data(json.utf8))
        let board = ServerStats.leaderboard(from: response, sort: .rating, viewer: nil)
        #expect(board.ranked.map(\.neighs) == [18, 0])
        #expect(board.ranked.map(\.neighsPerGame) == [1.5, 0])

        let profile = #"{"player":\#(player),"rating":1100,"globalRank":3,"stats":{"gamesPlayed":12,"wins":5,"winRate":0.42,"avgScore":14.5,"knocks":9,"knocksLanded":4,"knockSuccess":0.44,"neighs":7,"neighsPerGame":0.58}}"#
        let decoded = try KedroJSON.decoder().decode(PlayerProfileResponse.self, from: Data(profile.utf8))
        #expect(decoded.stats?.neighs == 7)
        #expect(decoded.stats?.neighsPerGame == 0.58)

        let records = #"{"scope":"global","records":[{"kind":"mostNeighs","rows":[{"rank":1,"player":\#(player),"value":42,"isMe":false}]}]}"#
        let mapped = ServerStats.records(from: try KedroJSON.decoder().decode(RecordsResponse.self, from: Data(records.utf8)))
        #expect(mapped[.mostNeighs]?.first?.value == 42)
    }

    @Test("The Board row's stats line ends with the 🐴 count, when there is one")
    func boardLine() {
        #expect(LeaderboardRowView.neighsText(0, spoken: false) == nil)
        #expect(LeaderboardRowView.neighsText(12, spoken: false) == "🐴 12")
        #expect(LeaderboardRowView.neighsText(1, spoken: true) == "1 neigh")
        #expect(ProfileView.neighsValue(12, perGame: 1.5) == "12 · 1.5 a game")
    }
}
