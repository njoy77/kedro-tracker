import Foundation
import Testing
@testable import Kedro

@Suite("Kedro links")
struct KedroLinkTests {
    private let game = UUID(uuidString: "4F6C0000-0000-4000-8000-000000000001") ?? UUID()

    @Test("Invite links parse the game and the rotating token")
    func invite() {
        let link = KedroLink(url: URL(string: "https://kedro.app/t/4f6c0000-0000-4000-8000-000000000001?k=abc123") ?? URL(filePath: "/"))
        #expect(link == .invite(gameID: game, token: "abc123"))
        #expect(KedroLink(url: URL(string: "https://KEDRO.app/t/4f6c0000-0000-4000-8000-000000000001") ?? URL(filePath: "/")) == .invite(gameID: game, token: nil))
        #expect(KedroLink(url: URL(string: "https://kedro.app/t/4f6c0000-0000-4000-8000-000000000001?k=") ?? URL(filePath: "/")) == .invite(gameID: game, token: nil))
    }

    @Test("Other hosts, paths and bad IDs are rejected")
    func rejects() {
        for string in ["https://evil.example/t/4f6c0000-0000-4000-8000-000000000001", "https://kedro.app/x/4f6c0000-0000-4000-8000-000000000001", "https://kedro.app/t/nope", "kedro://table/nope", "kedro://other/x", "mailto:hi@kedro.app"] {
            #expect(KedroLink(url: URL(string: string) ?? URL(filePath: "/")) == nil, "\(string)")
        }
    }

    @Test("Links round-trip through their URL", arguments: [
        KedroLink.invite(gameID: UUID(), token: "t0k"),
        .invite(gameID: UUID(), token: nil),
        .table(gameID: UUID(), action: .recordRound),
        .table(gameID: UUID(), action: .reportHand),
        .table(gameID: UUID(), action: .openTable),
        .widget(kind: KedroWidgetKind.rivalry),
    ])
    func roundTrip(link: KedroLink) {
        #expect(KedroLink(url: link.url) == link)
    }

    @Test("Table links default to just opening the Table")
    func tableDefault() {
        #expect(KedroLink.table(gameID: game, action: .openTable).url.absoluteString == "kedro://table/4f6c0000-0000-4000-8000-000000000001")
        #expect(KedroLink(url: URL(string: "kedro://table/4f6c0000-0000-4000-8000-000000000001?action=bogus") ?? URL(filePath: "/")) == .table(gameID: game, action: .openTable))
    }
}

@Suite("Claim token store")
struct ClaimTokenStoreTests {
    private func makeStore() -> ClaimTokenStore {
        let suite = "kedro.tests.claims.\(UUID().uuidString)"
        return ClaimTokenStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    @Test("Records games per guest and keeps a token through offline launches")
    func record() throws {
        let store = makeStore()
        store.record(guestID: "g1", displayName: "Sam", gameID: "a", hostName: "Noah", claimToken: nil)
        #expect(store.redeemable().isEmpty)
        store.record(guestID: "g1", displayName: "Sam", gameID: "a", hostName: nil, claimToken: "tok")
        store.record(guestID: "g1", displayName: "Sam", gameID: "b", hostName: nil, claimToken: nil)
        let claim = try #require(store.pending().first)
        #expect(store.pending().count == 1)
        #expect(claim.gameIDs == ["a", "b"])
        #expect(claim.claimToken == "tok")
        #expect(claim.hostName == "Noah")
        #expect(store.redeemable().map(\.guestID) == ["g1"])
    }

    @Test("A second table's guest seat is a second claim")
    func secondGuest() {
        let store = makeStore()
        store.record(guestID: "g1", displayName: "Sam", gameID: "a", hostName: "Noah", claimToken: "t1")
        store.record(guestID: "g2", displayName: "Sam", gameID: "b", hostName: "Priya", claimToken: "t2")
        #expect(store.pending().map(\.guestID) == ["g1", "g2"])
        store.remove(guestID: "g1")
        #expect(store.pending().map(\.guestID) == ["g2"])
        store.remove(guestID: "g2")
        #expect(store.pending().isEmpty)
    }

    @Test("Claims encode with sorted keys and omit a missing token")
    func encoding() throws {
        let claim = PendingGuestClaim(guestID: "g1", displayName: "Sam", claimToken: nil, gameIDs: ["a"], hostName: "Noah", updatedAt: Date(timeIntervalSince1970: 0))
        let json = String(data: try SharedJSON.encoder().encode(claim), encoding: .utf8)
        #expect(json == #"{"displayName":"Sam","gameIDs":["a"],"guestID":"g1","hostName":"Noah","updatedAt":"1970-01-01T00:00:00Z"}"#)
    }
}

@Suite("Live Activity buttons", .serialized)
@MainActor
struct LiveActivityActionTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "kedro.tests.inbox.\(UUID().uuidString)") ?? .standard
    }

    @Test("A tap survives a cold launch through the app group, once")
    func coldLaunch() {
        let defaults = defaults()
        LiveActivityActionInbox.handler = nil
        // Whole seconds: the app group stores ISO 8601 dates.
        let request = LiveActivityActionRequest(action: .recordRound, gameID: "game", requestedAt: Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down)))
        LiveActivityActionInbox.post(request, defaults: defaults)
        #expect(LiveActivityActionInbox.take(defaults: defaults) == request)
        #expect(LiveActivityActionInbox.take(defaults: defaults) == nil)
    }

    @Test("Stale taps are dropped")
    func expired() {
        let defaults = defaults()
        LiveActivityActionInbox.handler = nil
        let old = LiveActivityActionRequest(action: .reportHand, gameID: "game", requestedAt: .now.addingTimeInterval(-600))
        LiveActivityActionInbox.post(old, defaults: defaults)
        #expect(LiveActivityActionInbox.take(defaults: defaults) == nil)
    }

    @Test("A running app gets the tap directly, and the Table takes it once")
    func handler() {
        let defaults = defaults()
        let controller = LiveActivityController()
        LiveActivityActionInbox.handler = { controller.receive($0) }
        defer { LiveActivityActionInbox.handler = nil }
        let game = GameID()
        let request = LiveActivityActionRequest(action: .recordRound, gameID: LiveActivityController.key(game), requestedAt: .now)
        LiveActivityActionInbox.post(request, defaults: defaults)
        #expect(LiveActivityActionInbox.take(defaults: defaults) == nil)
        #expect(controller.pendingAction == request)
        #expect(controller.takePendingAction(for: GameID()) == nil)
        #expect(controller.takePendingAction(for: game) == .recordRound)
        #expect(controller.takePendingAction(for: game) == nil)
    }
}
