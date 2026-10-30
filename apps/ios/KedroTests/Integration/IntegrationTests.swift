import Foundation
import Testing
@testable import Kedro

/// The seams between features: Stats → Table, Stats → widgets, broadcasts → the Live Activity,
/// the account sync on sign-in.
@Suite("Integration")
struct IntegrationTests {
    @Test("Game end gets ratings, badges and Hall of Shame from Stats, keyed by seat")
    func gameEndInsights() throws {
        let state = PreviewData.sampleState(throughRound: 8, finished: true)
        let snapshot = StatsSnapshot.preview
        let progression = try #require(snapshot.gameEnd(for: state.gameID, viewer: PreviewData.noah.ref))
        let insights = GameEndInsights(progression, in: state)
        let seats = Set(state.seats.map(\.id))
        #expect(!insights.ratings.isEmpty)
        #expect(Set(insights.ratings.keys).isSubset(of: seats))
        for change in progression.ratingChanges where change.isRated {
            let seat = try #require(state.seats.first { $0.player == change.player }?.id)
            #expect(insights.ratings[seat]?.after == change.displayAfter)
        }
        #expect(insights.badges.allSatisfy { seats.contains($0.seat) && $0.lineID?.hasPrefix("BG-") == true })
    }

    @Test("The Table's titles come from Stats once it has loaded")
    func tableTitles() {
        let state = PreviewData.sampleState(throughRound: 5, finished: false)
        let titles: [SeatID: TitleID] = [PreviewData.anaSeat: .regular]
        let loaded = TableInsights.stats(titles: titles, isLoaded: true, store: InMemoryGameStore(), viewer: nil, options: StatsOptions())
        let ana = state.seats[1]
        #expect(loaded.titleID(ana) == TitleID.regular.rawValue)
        #expect(loaded.titleID(state.seats[0]) == nil)
        var withTitle = ana
        withTitle.titleID = "TI-05"
        let loading = TableInsights.stats(titles: [:], isLoaded: false, store: InMemoryGameStore(), viewer: nil, options: StatsOptions())
        #expect(loading.titleID(withTitle) == "TI-05")
    }

    @Test("The widget snapshot carries standing, rivalry and the next badge")
    func widgetSnapshot() throws {
        let snapshot = StatsSnapshot.preview
        // Whole seconds: the shared JSON dates are ISO 8601 without fractions.
        let now = Date(timeIntervalSince1970: 1_792_900_000)
        let widget = snapshot.widgetSnapshot(for: PreviewData.noah.ref, name: "Noah", avatar: nil, voice: Voice(level: .clean), now: now)
        #expect(widget.playerName == "Noah")
        let standing = try #require(widget.standing)
        #expect(standing.gamesPlayed > 5)
        #expect(standing.isRanked)
        let rivalry = try #require(widget.rivalry)
        #expect(rivalry.rivalID?.hasPrefix("p:") == true || rivalry.rivalID?.hasPrefix("g:") == true)
        #expect(!rivalry.line.isEmpty)
        let data = try SharedJSON.encoder().encode(widget)
        #expect(try SharedJSON.decoder().decode(WidgetSnapshot.self, from: data) == widget)
    }

    @Test("A server broadcast resolves to this phone's row and button")
    func broadcastResolution() throws {
        let state = PreviewData.sampleState(throughRound: 5, finished: false)
        let viewer = LiveActivityContent.Viewer(seat: nil, isScorekeeper: false)
        var broadcast = try #require(LiveActivityContent.contentState(for: state, viewer: viewer, voice: Voice(level: .clean)))
        broadcast.action = LiveActivityButton(kind: .recordRound, title: "Record Round 6")
        broadcast.actionSeats = [PreviewData.noahSeat.rawValue]

        let noah = broadcast.resolved(for: PreviewData.noahSeat.rawValue)
        #expect(noah.myRow?.id == PreviewData.noahSeat.rawValue)
        #expect(noah.action?.kind == .recordRound)
        #expect(noah.actionSeats == nil)
        let ana = broadcast.resolved(for: PreviewData.anaSeat.rawValue)
        #expect(ana.myRow?.id == PreviewData.anaSeat.rawValue)
        #expect(ana.action == nil)
        let watcher = broadcast.resolved(for: nil)
        #expect(watcher.myRow == nil)
        #expect(watcher.action == nil)

        // Content a phone built for itself is already resolved.
        var local = broadcast
        local.actionSeats = nil
        #expect(local.resolved(for: PreviewData.anaSeat.rawValue) == local)
    }

    @Test("Sign-in sends the profile with its title, then claims every guest history")
    func accountSync() async throws {
        let http = MockHTTP { request in
            switch (request.method, request.path) {
            case ("PUT", "/v1/players/me"):
                return (200, MockHTTP.json(Player(id: PreviewData.noah.id, displayName: "Noah", handle: Handle(constant: "noah"), avatar: .curated(.crow))))
            case ("POST", "/v1/claims"):
                return (200, MockHTTP.json(ClaimResult(guestId: GuestID(), gamesClaimed: 2)))
            default:
                return (404, Data("{}".utf8))
            }
        }
        let defaults = try #require(UserDefaults(suiteName: "kedro.tests.account.\(UUID().uuidString)"))
        PendingClaims.add("CODE-123456", defaults: defaults)
        let clip = ClaimTokenStore(defaults: defaults)
        clip.record(guestID: GuestID().uuidString, displayName: "Sam", gameID: GameID().uuidString, hostName: "Noah", claimToken: "clip-token-abcdef")
        var claimed = 0
        let account = AccountSync(api: .mock(http), clipClaims: clip, defaults: defaults) { claimed = $0 }

        var profile = PreviewData.noahProfile
        profile.titleID = "TI-02"
        #expect(await account.uploadProfile(profile) == .saved)
        let put = try #require(http.requests.first { $0.method == "PUT" }?.body)
        let sent = try #require(try JSONSerialization.jsonObject(with: put) as? [String: Any])
        #expect(sent["titleId"] as? String == "TI-02")

        #expect(await account.claimGuestHistory(guestToken: "guest-token-123456") == 6)
        #expect(claimed == 6)
        #expect(http.requests.filter { $0.path == "/v1/claims" }.count == 3)
        #expect(PendingClaims.all(defaults: defaults).isEmpty)
        #expect(clip.pending().isEmpty)
    }

    @Test("A taken handle comes back as handleTaken; a guest profile isn't sent")
    func profileConflicts() async {
        let http = MockHTTP { _ in (409, Data(#"{"error":"handleTaken","message":"taken"}"#.utf8)) }
        let account = AccountSync(api: .mock(http))
        #expect(await account.uploadProfile(PreviewData.noahProfile) == .handleTaken)
        var guest = PreviewData.noahProfile
        guest.identity = .guest(GuestID())
        #expect(await account.uploadProfile(guest) == .notSent)
    }

    @Test("A guest's own seat carries the hash of its claim token, never the token")
    func claimTokenHash() {
        let profile = LocalProfile(identity: .guest(GuestID()), displayName: "Sam", claimToken: "secret-token")
        let seat = profile.seat(order: 0, device: DeviceID(), languageLevel: .clean, gamesPlayed: 0)
        #expect(seat.claimTokenHash == LocalProfile.claimTokenHash("secret-token"))
        #expect(seat.claimTokenHash?.count == 64)
        #expect(PreviewData.noahProfile.seat(order: 0, device: DeviceID(), languageLevel: .clean, gamesPlayed: 0).claimTokenHash == nil)
    }
}
