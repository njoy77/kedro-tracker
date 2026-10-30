import Foundation
import Testing
@testable import Kedro

@Suite("Talk sheet: sending taunts")
struct TalkComposerTests {
    private let blocking = TauntFilter(blocklist: TauntBlocklist(
        version: 1, blockedSHA256: [TauntBlocklist.hash("zorblax")], profanityStems: [], profanityWords: []
    ))

    private func session(as identity: LocalIdentity = PreviewData.noahIdentity, liveKnock: Bool = false) -> GameSession {
        let operations = PreviewData.sampleOperations(throughRound: 5, finished: false, liveKnock: liveKnock)
        return GameSession(
            gameID: PreviewData.sampleGameID, operations: operations, store: InMemoryGameStore(operations: operations),
            transport: LocalOnlyTransport(), identity: identity, clock: HybridLogicalClock(device: identity.deviceID)
        )
    }

    private func services(_ api: FakeTrashTalkAPI = FakeTrashTalkAPI()) -> TalkServices {
        TalkServices(moderation: ModerationStore(defaults: scratchDefaults()), sound: RecordingSoundPlayer(), api: api, filter: blocking)
    }

    private func preferences(under18: Bool = false) -> AppPreferences {
        let preferences = AppPreferences(defaults: scratchDefaults())
        preferences.isUnder18 = under18
        return preferences
    }

    private func myTaunts(_ session: GameSession) -> [TauntRecord] {
        session.state.taunts.filter { $0.from == PreviewData.noahSeat }
    }

    @Test("Three canned taunts go out; the fourth gets T-10")
    func cannedLimit() async {
        let session = session()
        let composer = TalkComposer(session: session, target: .seat(PreviewData.anaSeat))
        let services = services()
        let prefs = preferences()
        for id in ["TT-10", "TT-11", "TT-12"] {
            composer.selectedTauntID = id
            #expect(await composer.send(services: services, preferences: prefs))
        }
        #expect(myTaunts(session).count == 3)
        #expect(!composer.allowance.canSend)
        composer.selectedTauntID = "TT-13"
        #expect(!composer.canSend(preferences: prefs))
        #expect(!(await composer.send(services: services, preferences: prefs)))
        #expect(composer.notice == .rateLimited)
        #expect(myTaunts(session).count == 3)
    }

    @Test("One custom taunt per round, checked by the server")
    func customLimit() async {
        let session = session()
        let api = FakeTrashTalkAPI()
        let services = services(api)
        let prefs = preferences()
        let composer = TalkComposer(session: session, target: .table)
        composer.mode = .custom
        composer.customText = "  if sam lands this   i'm moving  "
        #expect(await composer.send(services: services, preferences: prefs))
        #expect(myTaunts(session).last?.content == .custom(text: "if sam lands this i'm moving"))
        #expect(api.calls == [.check("if sam lands this i'm moving")])

        composer.customText = "another one"
        #expect(!composer.canSend(preferences: prefs))
        #expect(!(await composer.send(services: services, preferences: prefs)))
        #expect(composer.notice == .rateLimited)
        // Canned ones still fit.
        composer.mode = .canned
        composer.selectedTauntID = "TT-10"
        #expect(await composer.send(services: services, preferences: prefs))
    }

    @Test("Blocked custom taunts don't go out and show T-12")
    func blocked() async {
        let session = session()
        let composer = TalkComposer(session: session, target: .table)
        composer.mode = .custom
        composer.customText = "you zorblax"
        #expect(!(await composer.send(services: services(), preferences: preferences())))
        #expect(composer.notice == .blocked)
        #expect(myTaunts(session).isEmpty)
        // A blocked one doesn't use up the custom allowance.
        #expect(composer.allowance.canSendCustom)
    }

    @Test("Custom text is capped at 80 characters as it's typed")
    func cap() {
        let composer = TalkComposer(session: session(), target: .table)
        composer.customText = String(repeating: "x", count: 95)
        #expect(composer.customText.count == 80)
    }

    @Test("Under 18: canned only")
    func under18() async {
        let composer = TalkComposer(session: session(), target: .table)
        let prefs = preferences(under18: true)
        #expect(!composer.canWriteCustom(preferences: prefs))
        composer.mode = .custom
        composer.customText = "hello"
        #expect(!composer.canSend(preferences: prefs))
        #expect(!(await composer.send(services: services(), preferences: prefs)))
    }

    @Test("Watchers send canned taunts only")
    func watcher() async {
        let watcher = LocalIdentity(deviceID: DeviceID(), player: PreviewData.priya.ref, displayName: "Priya")
        let session = session(as: watcher)
        #expect(session.mySeat == nil)
        let composer = TalkComposer(session: session, target: .seat(PreviewData.noahSeat))
        let prefs = preferences()
        #expect(!composer.canWriteCustom(preferences: prefs))
        #expect(composer.targetSeats.count == 5)
        composer.selectedTauntID = "TT-10"
        #expect(await composer.send(services: services(), preferences: prefs))
        let sent = session.state.taunts.last
        #expect(sent?.from == nil)
        #expect(sent?.fromName == "Priya")
    }

    @Test("Never aimed at yourself")
    func notAtMe() {
        let composer = TalkComposer(session: session(), target: .seat(PreviewData.noahSeat))
        #expect(composer.target == .table)
        #expect(!composer.targetSeats.contains { $0.id == PreviewData.noahSeat })
    }

    @Test("Finished games are read-only")
    func finished() async {
        let operations = PreviewData.sampleOperations(throughRound: 8, finished: true)
        let session = GameSession(
            gameID: PreviewData.sampleGameID, operations: operations, store: InMemoryGameStore(operations: operations),
            transport: LocalOnlyTransport(), identity: PreviewData.noahIdentity, clock: HybridLogicalClock(device: PreviewData.noahPhone)
        )
        let composer = TalkComposer(session: session, target: .table)
        composer.selectedTauntID = "TT-10"
        #expect(!composer.canSend(preferences: preferences()))
        #expect(!(await composer.send(services: services(), preferences: preferences())))
    }

    @Test("Visible taunts drop muted, blocked and reported senders")
    func visibleTaunts() async throws {
        let session = session(liveKnock: true) // Ana → Sam: TT-01
        let services = services()
        let prefs = preferences()
        #expect(services.visibleTaunts(in: session.state, preferences: prefs).count == 1)
        services.moderation.mute(PreviewData.anaSeat, scope: .thisGame, in: PreviewData.sampleGameID)
        #expect(services.visibleTaunts(in: session.state, preferences: prefs).isEmpty)
        services.moderation.unmute(PreviewData.anaSeat, in: PreviewData.sampleGameID)
        services.block(PreviewData.ana.ref)
        #expect(services.visibleTaunts(in: session.state, preferences: prefs).isEmpty)
        services.unblock(PreviewData.ana.ref)
        let taunt = try #require(session.state.taunts.first)
        services.report(taunt, reason: .abuse)
        #expect(services.visibleTaunts(in: session.state, preferences: prefs).isEmpty)
    }
}
