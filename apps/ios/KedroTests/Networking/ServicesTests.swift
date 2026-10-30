import Foundation
import Testing
@testable import Kedro

@Suite("Invites, nearby alert and directory")
@MainActor
struct ServicesTests {
    // MARK: Invites

    @Test("QR links parse, with or without the code, and round-trip")
    func inviteLinks() throws {
        let game = GameID()
        let link = TableInvite.link(for: game, inviteCode: "abc_123")
        #expect(link.absoluteString == "https://kedro.app/t/\(game.uuidString.lowercased())?k=abc_123")

        let invite = try #require(TableInvite(url: link))
        #expect(invite.gameID == game)
        #expect(invite.inviteCode == "abc_123")
        #expect(invite.source == .link)

        let schemeURL = try #require(URL(string: "kedro://t/\(game.uuidString)"))
        let scheme = try #require(TableInvite(url: schemeURL))
        #expect(scheme.gameID == game)
        #expect(scheme.inviteCode == nil)

        for string in ["https://example.com/t/\(game.uuidString)", "https://kedro.app/t/not-a-game", "https://kedro.app/u/\(game.uuidString)"] {
            let url = try #require(URL(string: string))
            #expect(TableInvite(url: url) == nil, "\(string)")
        }
    }

    @Test("The saved-you-a-seat push payload becomes an invite")
    func pushPayload() throws {
        let game = GameID()
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["body": "Maya saved you a seat at Cold Deck."]],
            "kedro": ["kind": "seat", "gameId": game.uuidString, "host": "Maya", "word": "Cold Deck"],
        ]
        let invite = try #require(TableInvite(userInfo: userInfo))
        #expect(invite.gameID == game)
        #expect(invite.source == .savedSeat)
        #expect(invite.hostName == "Maya")
        #expect(invite.tableWord == "Cold Deck")

        let nearby = TableInvite(gameID: game, source: .nearbyAlert, hostName: "Maya")
        #expect(TableInvite(userInfo: nearby.userInfo) == nearby)
        #expect(TableInvite(userInfo: ["kedro": ["kind": "leaderboard"]]) == nil)
    }

    @Test("Opening a link sets the pending invite and prefetches the game")
    func pushServiceHandlesLinks() async throws {
        let push = PushService(api: .mock(MockHTTP()), defaults: UserDefaults(suiteName: "kedro.tests.push") ?? .standard)
        var prefetched: [GameID] = []
        push.prefetch = { prefetched.append($0) }
        let game = GameID()
        #expect(push.handle(TableInvite.link(for: game, inviteCode: "x")))
        let about = try #require(URL(string: "https://kedro.app/about"))
        #expect(!push.handle(about))
        #expect(push.pendingInvite?.gameID == game)
        #expect(await eventually { prefetched == [game] })
        push.consumeInvite()
        #expect(push.pendingInvite == nil)
    }

    @Test("Push tokens upload once per account, as lowercase hex")
    func pushTokenUpload() async throws {
        let http = MockHTTP { _ in (200, Data(#"{"ok":true}"#.utf8)) }
        let defaults = try #require(UserDefaults(suiteName: "kedro.tests.push-token"))
        defaults.removePersistentDomain(forName: "kedro.tests.push-token")
        let push = PushService(api: .mock(http), defaults: defaults)
        await push.didRegister(deviceToken: Data([0x0a, 0xff, 0x10]))
        await push.uploadToken()
        let posts = http.requests.filter { $0.path == "/v1/push/tokens" }
        #expect(posts.count == 1)
        let body = try #require(posts.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["token"] as? String == "0aff10")
        #expect(json["kind"] as? String == "apns")
        #expect(json["gameId"] == nil)
    }

    // MARK: Nearby alert

    @Test("Nearby alert: once per table, at most 3 a day")
    func alertPolicy() throws {
        var policy = NearbyAlertPolicy()
        let calendar = Calendar(identifier: .gregorian)
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 9)))
        let first = GameID()
        #expect(policy.shouldAlert(for: first, on: morning, calendar: calendar))
        policy.record(first, on: morning)
        #expect(!policy.shouldAlert(for: first, on: morning, calendar: calendar))
        for hour in 1...2 {
            let game = GameID()
            #expect(policy.shouldAlert(for: game, on: morning.addingTimeInterval(Double(hour) * 3600), calendar: calendar))
            policy.record(game, on: morning.addingTimeInterval(Double(hour) * 3600))
        }
        #expect(!policy.hasAlertsLeft(on: morning.addingTimeInterval(4 * 3600), calendar: calendar))
        #expect(!policy.shouldAlert(for: GameID(), on: morning.addingTimeInterval(4 * 3600), calendar: calendar))
        #expect(policy.shouldAlert(for: GameID(), on: morning.addingTimeInterval(24 * 3600), calendar: calendar))
    }

    @Test("The beacon payload round-trips in 32 bytes")
    func beaconPayload() throws {
        let beacon = NearbyBeacon(player: PlayerID(), game: GameID())
        #expect(beacon.encoded.count == 32)
        #expect(NearbyBeacon(encoded: beacon.encoded) == beacon)
        #expect(NearbyBeacon(encoded: Data([1, 2, 3])) == nil)
    }

    // MARK: Directory

    @Test("Search asks the server, and falls back to the cache offline")
    func directorySearch() async throws {
        let maya = PlayerSummary(id: PlayerID(), displayName: "Maya", handle: Handle(constant: "maya"), avatar: .curated(.spade))
        let http = MockHTTP { request in
            #expect(request.path == "/v1/players/search")
            #expect(request.query["q"] == "@may")
            return (200, MockHTTP.json(PlayerSearchResult(players: [maya])))
        }
        let local = LocalPlayerDirectory(store: InMemoryGameStore()) { nil }
        let directory = RemotePlayerDirectory(api: .mock(http), local: local, cache: PlayerCache(url: nil))
        #expect(try await directory.search("@may") == [maya])
        #expect(try await directory.player(maya.id) == maya)

        http.setResponder { _ in throw URLError(.notConnectedToInternet) }
        #expect(try await directory.search("maya") == [maya])
        #expect(try await directory.search("nobody").isEmpty)
        #expect(try await directory.search("  ").isEmpty)
    }

    @Test("Played With comes from finished games on this phone")
    func directoryPlayedWith() async throws {
        let store = InMemoryGameStore(operations: PreviewData.historyOperations)
        let local = LocalPlayerDirectory(store: store) { .player(PreviewData.noah.id) }
        let directory = RemotePlayerDirectory(api: .mock(MockHTTP(), token: nil), local: local, cache: PlayerCache(url: nil))
        let playedWith = try await directory.playedWith()
        #expect(!playedWith.isEmpty)
        let someone = try #require(playedWith.first)
        #expect(await directory.hasPlayedWith(someone.player.ref))
        #expect(!(await directory.hasPlayedWith(.player(PlayerID()))))
    }
}
