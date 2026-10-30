import Foundation
import Testing
@testable import Kedro

/// Regression tests for the review fixes: crash-proof folding and stats, clock drift, server
/// boards, claim codes and the block safeguard in the lobby.
@Suite("Review fixes")
@MainActor
struct ReviewFixTests {
    // MARK: Fold

    @Test("A GameFinished with a round numbered 0 is refused, not a crash")
    func finalRoundNumberZero() {
        var game = TestGame(players: 3)
        game.setUp()
        game.record([4, 10, 12], knocker: 0)
        let bad = Round(number: 0, hands: Dictionary(uniqueKeysWithValues: game.seats.map { ($0.id, 3) }), knocker: game.seat(0))
        game.add(.gameFinished(.init(reason: .completed, finalRounds: [bad])))
        let state = game.state
        #expect(state.status == .active)
        #expect(state.rounds.count == 1)
        #expect(state.lateOperations.count == 1)
    }

    @Test("finalRounds with hands for people who aren't seated are refused")
    func finalRoundsNotSeats() {
        var game = TestGame(players: 3)
        game.setUp()
        game.record([4, 10, 12], knocker: 0)
        var hands = Dictionary(uniqueKeysWithValues: game.seats.map { ($0.id, 3) })
        hands[PlayerRef.player(PlayerID()).seatID] = -2
        let bad = Round(number: 1, hands: hands, knocker: game.seat(0))
        game.add(.gameFinished(.init(reason: .completed, finalRounds: [bad])))
        #expect(game.state.status == .active)
        #expect(game.state.standings.map(\.total).sorted() == [-10, 10, 12])
    }

    @Test("A valid finish with authoritative finalRounds still applies")
    func validFinish() {
        var game = TestGame(players: 3)
        game.setUp()
        game.record([4, 10, 12], knocker: 0)
        game.add(.gameFinished(.init(reason: .completed, finalRounds: [game.round(1, [5, 10, 12], knocker: 0)])))
        #expect(game.state.status == .finished)
        #expect(game.state.rounds.first?.round.hands[game.seat(0)] == 5)
    }

    // MARK: Stats

    @Test("A claimed guest seated beside the claiming account counts once, without trapping")
    func claimedGuestBesideAccount() throws {
        var game = TestGame(players: 3)
        let guestID = GuestID()
        let guestSeat = Seat(player: .guest(guestID), displayName: "Sam", order: 3)
        game.setUp(start: false)
        game.add(.playerSeated(.init(seat: guestSeat)))
        game.add(.gameStarted(.init(seatOrder: game.seats.map(\.id) + [guestSeat.id], firstDealer: game.seat(0))))
        let hands = Dictionary(uniqueKeysWithValues: (game.seats.map(\.id) + [guestSeat.id]).enumerated().map { ($1, [4, 10, 12, 2][$0]) })
        game.add(.roundRecorded(.init(round: Round(number: 1, hands: hands, knocker: game.seat(1)))))
        game.add(.gameFinished(.init(reason: .completed, finalRounds: [])))
        let owner = game.seats[0].player
        var options = StatsOptions(aliases: [.guest(guestID): owner])
        options.minimumRounds = 1 // a one-round game, below the 3-round rule
        let snapshot = StatsSnapshot.build([game.state], options: options)
        let stats = try #require(snapshot.games.first)
        #expect(stats.participants.count == 3)
        // The owner's own seat is the one that counts (hand 4), not the guest's 2.
        #expect(stats.totals[owner] == 4)
        #expect(snapshot.record(owner)?.gamesPlayed == 1)
    }

    // MARK: Clock

    @Test("A remote clock far in the future can't drag this phone's clock with it")
    func remoteDriftCapped() {
        let now: Int64 = 1_761_000_000_000
        let clock = HybridLogicalClock(node: "me", now: { now })
        clock.receive(HLC(wallMs: now + 30 * 24 * 60 * 60 * 1000, counter: 0, node: "liar"))
        let next = clock.tick()
        #expect(next.wallMs <= now + HybridLogicalClock.maxRemoteDriftMs)
        clock.receive(HLC(wallMs: now + 1_000, counter: 4, node: "near"))
        #expect(clock.tick() > next)
    }

    // MARK: Server board

    @Test("The server's Global board maps onto the Board's rows")
    func serverBoardMapping() throws {
        let ana = PreviewData.ana
        let ben = PreviewData.ben
        let json = """
        {"scope":"global","sort":"rating","notYetRankedCount":0,"notYetRanked":[],
         "rows":[
          {"rank":1,"player":{"id":"\(ana.id.uuidString.lowercased())","displayName":"Ana","handle":"ana.k","avatar":{"kind":"curated","id":"spade"}},"value":1142,"rating":1142,"gamesPlayed":30,"wins":12,"winRate":0.4,"avgScore":31.2,"knocks":40,"knocksLanded":22,"knockSuccess":0.55,"isMe":false},
          {"rank":2,"player":{"id":"\(ben.id.uuidString.lowercased())","displayName":"Ben","handle":"ben","avatar":{"kind":"curated","id":"spade"}},"value":1086,"rating":1086,"gamesPlayed":9,"wins":2,"winRate":0.22,"avgScore":40.1,"knocks":5,"knocksLanded":1,"knockSuccess":null,"isMe":true}
         ]}
        """
        let response = try KedroJSON.decoder().decode(LeaderboardResponse.self, from: Data(json.utf8))
        let board = ServerStats.leaderboard(from: response, sort: .rating, viewer: ben.ref)
        #expect(board.ranked.map(\.identity.name) == ["Ana", "Ben"])
        #expect(board.ranked.map(\.valueText) == ["1,142", "1,086"])
        #expect(board.viewerIndex == 1)
        #expect(board.ranked.first?.rank?.label == "1")
    }

    @Test("Upload answers keep ops refused only for a clock running ahead")
    func clockAheadDecoding() throws {
        let op = UUID()
        let json = #"{"accepted":[],"duplicates":[],"rejected":[{"opId":"\#(op.uuidString.lowercased())","reason":"clockAhead"},{"opId":null,"reason":"invalid"}]}"#
        let result = try KedroJSON.decoder().decode(OpsUploadResult.self, from: Data(json.utf8))
        #expect(result.clockAhead == [op])
        // Older servers send no `rejected`.
        let old = try KedroJSON.decoder().decode(OpsUploadResult.self, from: Data(#"{"accepted":[],"duplicates":[]}"#.utf8))
        #expect(old.rejected.isEmpty)
    }

    // MARK: Lobby

    private func makeApp() -> AppModel {
        let defaults = UserDefaults(suiteName: "kedro.tests.fixes.\(UUID().uuidString)") ?? .standard
        return AppModel(
            store: InMemoryGameStore(operations: PreviewData.historyOperations),
            preferences: AppPreferences(defaults: defaults),
            profiles: ProfileStore(container: nil, profile: PreviewData.noahProfile),
            deviceID: PreviewData.noahPhone
        )
    }

    @Test("Someone you blocked can't be added to your table")
    func blockedNotAdded() async throws {
        let app = makeApp()
        let lobby = try LobbyModel(app: app, claimCodes: InMemoryGuestClaimCodes(), isBlocked: { $0 == PreviewData.ana.ref })
        await lobby.add(PreviewData.ana)
        await lobby.add(PreviewData.ben)
        #expect(lobby.seats.map(\.displayName) == ["Noah", "Ben"])
        #expect(lobby.hasBlocked(PreviewData.ana.ref))
    }

    @Test("A guest added by name gets a claim hash; the code stays on this phone")
    func guestClaimCode() async throws {
        let app = makeApp()
        let codes = InMemoryGuestClaimCodes()
        let lobby = try LobbyModel(app: app, claimCodes: codes, isBlocked: { _ in false })
        let guest = GuestID()
        await lobby.add(Seat(player: .guest(guest), displayName: "Sam", order: lobby.seats.count, gamesPlayed: 0))
        let seat = try #require(lobby.seats.first { $0.player == .guest(guest) })
        let code = try #require(codes.code(for: guest))
        #expect(seat.claimTokenHash == LocalProfile.claimTokenHash(code))
        #expect(code.count >= 16)
    }

    @Test("A local photo is never put in a seat")
    func localPhotoNotShared() {
        var profile = PreviewData.noahProfile
        profile.avatar = .photo(URL(filePath: "/var/mobile/Containers/avatar.jpg"))
        #expect(profile.seat(order: 0, device: DeviceID(), languageLevel: .clean, gamesPlayed: 0).avatar == nil)
        let remote = Avatar.photo(URL(string: "https://api.kedro.app/photos/abc?v=1")!)
        profile.avatar = remote
        #expect(profile.seat(order: 0, device: DeviceID(), languageLevel: .clean, gamesPlayed: 0).avatar == remote)
    }

    // MARK: Joining

    @Test("A late guest phone finds the seat the host typed in with its name")
    func guestSeatMatch() {
        var game = TestGame(players: 3)
        game.setUp(start: false)
        let typed = Seat(player: .guest(GuestID()), displayName: "Sam", order: 3)
        game.add(.playerSeated(.init(seat: typed)))
        let phone = LocalProfile(identity: .guest(GuestID()), displayName: "sam ")
        #expect(TableJoiner.guestSeat(matching: phone, in: game.state)?.id == typed.id)
        let stranger = LocalProfile(identity: .guest(GuestID()), displayName: "Jo")
        #expect(TableJoiner.guestSeat(matching: stranger, in: game.state) == nil)
        var linked = typed
        linked.deviceID = DeviceID()
        game.add(.playerSeated(.init(seat: linked)))
        #expect(TableJoiner.guestSeat(matching: phone, in: game.state) == nil)
    }

    @Test("Claimed guests count as the viewer")
    func claimedGuestAliases() throws {
        let defaults = try #require(UserDefaults(suiteName: "kedro.tests.claimed.\(UUID().uuidString)"))
        let claimed = ClaimedGuests(defaults: defaults)
        let guest = GuestID()
        claimed.record([guest])
        let me = PlayerRef.player(PlayerID())
        #expect(claimed.aliases(for: me) == [.guest(guest): me])
        #expect(ClaimedGuests(defaults: defaults).guestIDs == [guest])
    }
}
