import Foundation
import Testing
@testable import Kedro

@Suite("Server Wrapped (GET /v1/players/me/wrapped)")
struct WrappedResponseTests {
    private let noah = PlayerID(uuidString: "000000aa-0000-4000-8000-000000000001")!

    /// The shape the API sends (apps/api/test/progression.test.ts), trimmed to a few entries, with
    /// a badge, title and Hall of Shame category this app doesn't know.
    private let json = """
    {
      "year": 2026,
      "availability": { "kind": "available" },
      "summary": {
        "year": 2026, "games": 12, "rounds": 96, "hours": 6.5, "people": 4,
        "wins": 12, "winRate": 1, "finishes": { "1": 12 }, "isWinRateHigh": true,
        "ratingLine": [{ "date": "2026-10-12T20:00:00Z", "rating": 1000 }, { "date": "2026-10-13T21:01:13Z", "rating": 1032 }],
        "ratingStart": 1000, "ratingPeak": 1032, "ratingNow": 1032, "currentRank": 1,
        "knocks": 36, "knockSuccess": 0.67, "favoriteKnockValue": 4,
        "bestKnock": { "gameId": "00000001-0000-4000-9000-000000000000", "tableWord": "Cold Deck", "date": "2026-10-13T21:01:13Z", "roundNumber": 3, "hand": 9, "lowestOther": 12 },
        "worstKnock": null,
        "nemesis": null,
        "victim": { "person": { "kind": "guest", "id": "000000bb-0000-4000-8000-000000000009", "displayName": "Sam" }, "count": 12 },
        "redKings": 3, "ghostHands": 1, "biggestHand": 41,
        "tauntsSent": 2, "favoriteTaunt": { "kind": "canned", "id": "TT-01" }, "mostTaunted": null,
        "badges": [
          { "badge": "BG-01", "gameId": "00000001-0000-4000-9000-000000000000", "tableWord": "Cold Deck", "roundNumber": null, "earnedAt": "2026-10-13T21:01:13Z" },
          { "badge": "BG-99", "gameId": null, "tableWord": null, "roundNumber": null, "earnedAt": null }
        ],
        "titles": ["TI-04", "TI-77"],
        "shame": [
          { "category": "worstHand", "person": { "kind": "player", "id": "000000aa-0000-4000-8000-000000000001", "displayName": "Noah" }, "gameId": "00000001-0000-4000-9000-000000000000", "tableWord": "Cold Deck", "finishedAt": "2026-10-13T21:01:13Z", "roundNumber": 8, "value": 21, "hand": 21, "low": null, "finishPosition": null },
          { "category": "slowestDeal", "person": { "kind": "player", "id": "000000aa-0000-4000-8000-000000000001", "displayName": "Noah" }, "gameId": "00000001-0000-4000-9000-000000000000", "tableWord": "Cold Deck", "finishedAt": "2026-10-13T21:01:13Z", "roundNumber": null, "value": 1, "hand": null, "low": null, "finishPosition": null }
        ],
        "persona": { "id": "closer", "name": "The Closer", "copyId": "WR-19" }
      }
    }
    """

    @Test("Maps onto the story cards' summary; unknown IDs are skipped, not fatal")
    func mapsSummary() throws {
        let response = try KedroJSON.decoder().decode(WrappedResponse.self, from: Data(json.utf8))
        #expect(response.availability.value == .available)
        let identity = StatsParticipant(ref: .player(noah), seatedAs: .player(noah), name: "Noah")
        let summary = try #require(response.wrappedSummary(for: identity))
        #expect(summary.player == .player(noah))
        #expect(summary.games == 12)
        #expect(summary.finishes == [1: 12])
        #expect(summary.ratingLine.map(\.rating) == [1000, 1032])
        #expect(summary.currentRank == Rank(position: 1, isShared: false))
        #expect(summary.bestKnock?.outcome == .landed)
        #expect(summary.bestKnock?.hand == 9)
        #expect(summary.victim?.name == "Sam")
        #expect(summary.victim?.ref.guestID != nil)
        #expect(summary.favoriteTaunt == .canned(id: "TT-01"))
        #expect(summary.badges.map(\.badge) == [.outOfTheGate])
        #expect(summary.titles == [.theGhost])
        #expect(summary.shame.map(\.category) == [.worstHand])
        #expect(summary.shame.first?.identity.name == "Noah")
        #expect(summary.persona == .closer)
        #expect(WrappedCard.cards(for: summary).count == 12)
    }

    @Test("Availability kinds, and a newer server's unknown one")
    func availability() throws {
        func decode(_ text: String) throws -> WrappedAvailability? {
            try KedroJSON.decoder().decode(WrappedResponse.Availability.self, from: Data(text.utf8)).value
        }
        #expect(try decode(#"{"kind":"needsGames","played":4,"needed":10}"#) == .needsGames(played: 4, needed: 10))
        #expect(try decode(#"{"kind":"arrives","at":"2026-12-01T05:00:00Z"}"#) == .arrives(Date(timeIntervalSince1970: 1_796_101_200)))
        #expect(try decode(#"{"kind":"someday"}"#) == nil)
    }

    @Test("The phone and the server: whichever is further along")
    func furthest() {
        let release = Date(timeIntervalSince1970: 1_796_101_200)
        let few = WrappedAvailability.needsGames(played: 3, needed: 10)
        let more = WrappedAvailability.needsGames(played: 7, needed: 10)
        #expect(few.furthest(nil) == few)
        #expect(few.furthest(more) == more)
        #expect(more.furthest(few) == more)
        #expect(few.furthest(.arrives(release)) == .arrives(release))
        #expect(WrappedAvailability.arrives(release).furthest(.available) == .available)
        #expect(WrappedAvailability.available.furthest(few) == .available)
    }
}
