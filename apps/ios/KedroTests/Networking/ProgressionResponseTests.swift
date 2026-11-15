import Foundation
import Testing
@testable import Kedro

@Suite("Server progression (GET /v1/players/:id/progression)")
struct ProgressionResponseTests {
    /// The shape the API sends (apps/api/test/progression.test.ts), with a badge and a title this
    /// app doesn't know yet.
    private let json = """
    {
      "playerId": "000000aa-0000-4000-8000-000000000001",
      "badges": [
        { "badge": "BG-01", "gameId": "00000001-0000-4000-9000-000000000000", "tableWord": "Cold Deck", "roundNumber": null, "earnedAt": "2026-10-13T21:01:13Z" },
        { "badge": "BG-15", "gameId": "00000001-0000-4000-9000-000000000000", "tableWord": "Cold Deck", "roundNumber": 8, "earnedAt": "2026-10-13T21:01:13Z" },
        { "badge": "BG-99", "gameId": null, "tableWord": null, "roundNumber": null, "earnedAt": null }
      ],
      "nextUp": [{ "badge": "BG-04", "value": 12, "target": 25 }],
      "titles": { "earned": ["TI-01", "TI-04"], "held": [], "display": "TI-04" },
      "hallOfShameEntries": 2,
      "rivals": []
    }
    """

    @Test("Decodes badges and the title; unknown IDs are skipped, not fatal")
    func decodes() throws {
        let response = try KedroJSON.decoder().decode(PlayerProgressionResponse.self, from: Data(json.utf8))
        #expect(response.hallOfShameEntries == 2)
        #expect(Set(response.awards.keys) == [.outOfTheGate, .ghostHand])
        #expect(response.awards[.ghostHand]?.roundNumber == 8)
        #expect(response.awards[.ghostHand]?.tableWord == "Cold Deck")
        #expect(response.awards[.ghostHand]?.date != nil)
        #expect(response.displayTitle == .theGhost)

        var unknownTitle = response
        unknownTitle.titles.display = "TI-77"
        #expect(unknownTitle.displayTitle == nil)
    }
}
