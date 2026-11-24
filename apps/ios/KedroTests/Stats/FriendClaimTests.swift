import Foundation
import Testing
@testable import Kedro

/// A friend's claimed guest is the friend's account on this phone too (one person, from game 1),
/// not only the viewer's own claims. Found when web-era "Rhys" stayed a separate Nemesis from the
/// Rhysoroni account after Rhys claimed his history.
@Suite("Other people's claimed guests")
struct FriendClaimTests {
    private func freshClaims() throws -> ClaimedGuests {
        let defaults = try #require(UserDefaults(suiteName: "kedro.tests.friendClaims.\(UUID().uuidString)"))
        return ClaimedGuests(defaults: defaults)
    }

    @Test("Nemesis and head-to-head merge a friend's web-era guest with their account")
    func friendMerges() throws {
        let me = TestPerson.player("NJOY")
        let webRhys = TestPerson.guest("Rhys"), rhysoroni = TestPerson.player("Rhysoroni")
        let other = TestPerson.player("Ana")
        var history = StatsHistory()
        // The web years: Rhys finishes ahead three times.
        for _ in 0..<3 { history.win([me, webRhys, other], winner: 1) }
        // The app: Rhysoroni once, Ana twice.
        history.win([me, rhysoroni, other], winner: 1)
        for _ in 0..<2 { history.win([me, rhysoroni, other], winner: 2) }

        let split = history.snapshot()
        #expect(split.headToHead(me.ref, rhysoroni.ref).gamesTogether == 3)
        // Split in two: web Rhys (3 ahead) is the nemesis, Rhysoroni a stranger with 1.
        #expect(split.record(me.ref)?.nemesis()?.ref == webRhys.ref)

        let claims = try freshClaims()
        claims.replaceAccounts([try #require(webRhys.ref.guestID): try #require(rhysoroni.ref.playerID)])
        let merged = history.snapshot(StatsOptions(aliases: claims.aliases(for: me.ref)))
        let h2h = merged.headToHead(me.ref, rhysoroni.ref)
        #expect(h2h.gamesTogether == 6)
        // Ahead of NJOY in the 4 games Rhys won (the losers tie at 5 in the other 2).
        #expect(h2h.bAhead == 4)
        #expect(merged.record(me.ref)?.nemesis()?.ref == rhysoroni.ref)
        #expect(merged.record(me.ref)?.nemesis()?.count == 4)
        #expect(merged.records[webRhys.ref] == nil)
        #expect(merged.record(rhysoroni.ref)?.gamesPlayed == 6)
    }

    @Test("Own claims count as the viewer; the server's list wins, persists, and is replaced each pull")
    func aliasMap() throws {
        let claims = try freshClaims()
        let me = PlayerRef.player(PlayerID())
        let mine = GuestID(), friends = GuestID(), friend = PlayerID()
        claims.record([mine])
        claims.replaceAccounts([friends: friend])
        #expect(claims.aliases(for: me) == [.guest(mine): me, .guest(friends): .player(friend)])
        // Signed out: other people's claims still apply.
        #expect(claims.aliases(for: nil) == [.guest(friends): .player(friend)])

        // The server says the "mine" seat belongs to someone else (signed in as another account).
        let someoneElse = PlayerID()
        claims.replaceAccounts([mine: someoneElse])
        #expect(claims.aliases(for: me)[.guest(mine)] == .player(someoneElse))
        #expect(claims.aliases(for: me)[.guest(friends)] == nil)

        let defaults = try #require(UserDefaults(suiteName: "kedro.tests.friendClaims.persist.\(UUID().uuidString)"))
        ClaimedGuests(defaults: defaults).replaceAccounts([friends: friend])
        #expect(ClaimedGuests(defaults: defaults).accounts == [friends: friend])
        let reloaded = ClaimedGuests(defaults: defaults)
        reloaded.resetAccounts()
        #expect(ClaimedGuests(defaults: defaults).accounts.isEmpty)
    }

    @Test("The games list decodes claims; older servers send none; bad pairs are skipped")
    func decodesClaims() throws {
        let guest = "00000000-0000-4000-8000-0000000000aa", player = "000000aa-0000-4000-8000-000000000001"
        let json = """
        { "games": [], "claimedGuestIds": [], "claims": { "\(guest)": "\(player)", "not-a-uuid": "\(player)" } }
        """
        let response = try KedroJSON.decoder().decode(MyGamesResponse.self, from: Data(json.utf8))
        #expect(response.claims == [try #require(GuestID(uuidString: guest)): try #require(PlayerID(uuidString: player))])

        let older = try KedroJSON.decoder().decode(MyGamesResponse.self, from: Data(#"{ "games": [], "claimedGuestIds": [] }"#.utf8))
        #expect(older.claims == nil)

        let roundTrip = try KedroJSON.decoder().decode(MyGamesResponse.self, from: KedroJSON.encoder().encode(response))
        #expect(roundTrip.claims == response.claims)
    }
}
