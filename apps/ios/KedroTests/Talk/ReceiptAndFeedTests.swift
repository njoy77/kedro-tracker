import Foundation
import Testing
@testable import Kedro

@Suite("Receipts")
struct ReceiptTests {
    /// The §17 sample game, final: Noah 28, Ana 34, Cleo 65, Ben 67, Sam 70.
    private let state = PreviewData.sampleState(throughRound: 8, finished: true)

    private func keys(from sender: SeatID, to rival: SeatID) -> [String] {
        Receipts.options(in: state, from: sender, to: rival).map(\.key)
    }

    @Test("The winner gets Scoreboard; Rematch always fits")
    func winner() {
        #expect(keys(from: PreviewData.noahSeat, to: PreviewData.anaSeat) == ["RC-01", "RC-03"])
    }

    @Test("Ana on Noah: his failed knock, the knock she beat, and the gap")
    func chasing() throws {
        let options = Receipts.options(in: state, from: PreviewData.anaSeat, to: PreviewData.noahSeat)
        #expect(options.map(\.key) == ["RC-06", "RC-02", "RC-04", "RC-03"])

        let beat = try #require(options.first { $0.key == "RC-06" })
        #expect(beat.values == ["low": 3])
        #expect(beat.roundNumber == 3)
        #expect(beat.line(level: .clean) == "Your knock. My 3. Remember that.")

        let failed = try #require(options.first { $0.key == "RC-02" })
        #expect(failed.values == ["hand": 8])
        #expect(failed.line(level: .clean) == "Knocking on 8 is a choice. A bad choice.")
        #expect(failed.line(level: .spicy) == "Knocking on 8 is a choice. A shit choice.")
        let roast = try #require(Receipts.roast(for: failed, in: state))
        #expect(roast.contains("Noah knocked on 8"))

        let gap = try #require(options.first { $0.key == "RC-04" })
        #expect(gap.values == ["gap": 6])
    }

    @Test("Last place gets its own line")
    func lastPlace() {
        #expect(keys(from: PreviewData.noahSeat, to: PreviewData.samSeat).contains("RC-05"))
        #expect(!keys(from: PreviewData.samSeat, to: PreviewData.noahSeat).contains("RC-05"))
    }

    @Test("Every phone rebuilds the same line from the key")
    func rebuild() {
        let sent = Receipts.option("RC-02", in: state, from: PreviewData.anaSeat, to: PreviewData.noahSeat)
        #expect(sent?.values == ["hand": 8])
        #expect(Receipts.option("RC-01", in: state, from: PreviewData.anaSeat, to: PreviewData.noahSeat) == nil)
        #expect(Receipts.option("RC-99", in: state, from: PreviewData.anaSeat, to: PreviewData.noahSeat) == nil)
        #expect(Receipts.option("RC-03", in: state, from: PreviewData.anaSeat, to: PreviewData.anaSeat) == nil)
    }

    @Test("One per rival per game")
    func onePerRival() async throws {
        let operations = PreviewData.sampleOperations(throughRound: 8, finished: true)
        let session = GameSession(
            gameID: PreviewData.sampleGameID, operations: operations, store: InMemoryGameStore(operations: operations),
            transport: LocalOnlyTransport(), identity: PreviewData.noahIdentity, clock: HybridLogicalClock(device: PreviewData.noahPhone)
        )
        #expect(Receipts.recipients(in: session.state, from: PreviewData.noahSeat).count == 4)
        try await session.sendReceipt("RC-01", to: PreviewData.anaSeat)
        #expect(Receipts.hasSent(in: session.state, from: PreviewData.noahSeat, to: PreviewData.anaSeat))
        #expect(!Receipts.recipients(in: session.state, from: PreviewData.noahSeat).contains { $0.id == PreviewData.anaSeat })
        try await session.sendReceipt("RC-03", to: PreviewData.anaSeat) // refused by the fold
        #expect(session.state.receipts.filter { $0.to == PreviewData.anaSeat }.count == 1)
        #expect(session.state.receipts.first?.receiptKey == "RC-01")
    }

    @Test("Receipts only after the game is final")
    func onlyWhenFinished() async {
        let session = PreviewData.sampleSession(throughRound: 5)
        await #expect(throws: GameSession.SessionError.self) {
            try await session.sendReceipt("RC-03", to: PreviewData.anaSeat)
        }
    }

    @Test("The share image renders")
    func shareImage() throws {
        let noah = try #require(state.seat(PreviewData.noahSeat))
        let ana = try #require(state.seat(PreviewData.anaSeat))
        let option = try #require(Receipts.option("RC-01", in: state, from: noah.id, to: ana.id))
        #expect(ReceiptCard.image(state: state, option: option, sender: noah, rival: ana, level: .clean, scale: 2) != nil)
    }

    @Test("The card eyebrow is literal")
    func eyebrow() {
        #expect(Receipts.eyebrow(for: state) == "Cold Deck · Final · 8 rounds")
    }
}

@Suite("Feed")
struct FeedFilterTests {
    @Test("Shows rounds, knocks and records; hides taunts this phone doesn't show and blocked people's reactions")
    func filter() {
        let state = GameState.fold(PreviewData.sampleOperations(throughRound: 6, finished: false, liveKnock: true), gameID: PreviewData.sampleGameID)
        let all = FeedFilter.entries(in: state, visibleTaunts: Set(state.taunts.map(\.tauntId)), hides: { _ in false })
        #expect(all.count == state.feed.count)
        #expect(all.contains { if case .taunt = $0.kind { true } else { false } })

        let filtered = FeedFilter.entries(in: state, visibleTaunts: [], hides: { $0 == PreviewData.anaSeat })
        #expect(!filtered.contains { if case .taunt = $0.kind { true } else { false } })
        #expect(!filtered.contains { if case .reaction(_, let seat, _) = $0.kind { seat == PreviewData.anaSeat } else { false } })
        #expect(filtered.contains { if case .reaction(_, let seat, _) = $0.kind { seat == PreviewData.noahSeat } else { false } })
        #expect(filtered.filter { if case .roundSaved = $0.kind { true } else { false } }.count == 6)
        #expect(filtered.contains { if case .liveKnock = $0.kind { true } else { false } })
    }
}

@Suite("Taunt toasts")
struct LiveTalkMonitorTests {
    @Test("A new taunt toasts once, as 'Ana → Sam'; a muted sender's doesn't")
    func toasts() async throws {
        let app = AppModel.preview(seeded: false)
        let services = TalkServices(
            moderation: ModerationStore(defaults: scratchDefaults()), sound: RecordingSoundPlayer(), api: FakeTrashTalkAPI()
        )
        let session = PreviewData.sampleSession(throughRound: 5)
        let monitor = LiveTalkMonitor(session: session, app: app, services: services)
        let before = PreviewData.sampleState(throughRound: 5)
        let after = GameState.fold(PreviewData.sampleOperations(throughRound: 5, finished: false, liveKnock: true), gameID: PreviewData.sampleGameID)

        monitor.react(from: before, to: after)
        let toast = try #require(app.toasts.visible.last)
        #expect(toast.kind == .taunt)
        #expect(toast.eyebrow == "Ana → Sam")
        #expect(app.toasts.visible.filter { $0.kind == .taunt }.count == 1)

        // The same state again: no repeat.
        monitor.react(from: after, to: after)
        #expect(app.toasts.visible.filter { $0.kind == .taunt }.count == 1)

        // A fresh monitor with Ana muted shows nothing.
        app.toasts.dismissAll()
        services.moderation.mute(PreviewData.anaSeat, scope: .always, in: PreviewData.sampleGameID)
        LiveTalkMonitor(session: session, app: app, services: services).react(from: before, to: after)
        #expect(app.toasts.visible.isEmpty)
    }
}
