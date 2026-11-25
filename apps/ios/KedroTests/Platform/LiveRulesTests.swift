import Foundation
import Testing
@testable import Kedro

@Suite("Lock Screen rules cheat sheet")
struct LiveRulesTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "kedro.tests.liveRules.\(UUID().uuidString)"))
    }

    private func content(round: Int, phase: LiveGamePhase = .active, showsRules: Bool? = nil) -> LiveGameAttributes.ContentState {
        LiveGameAttributes.ContentState(
            phase: phase, roundNumber: round, plannedRounds: 8, metadataLine: "ROUND \(round) OF 8", rows: [],
            factLine: nil, liveKnockLine: nil, staleTemplate: "Last update {time}", action: nil, updatedAt: 0,
            showsRules: showsRules
        )
    }

    @Test("Says what Learn → Rules says")
    func matchesRules() throws {
        let rules = RulesContent.sections.flatMap(\.rules).map(\.text).joined(separator: "\n")
        let sheet = LiveRules.lines.map(\.text).joined(separator: "\n")
        // Every value on the sheet is the rules' value.
        for (card, rule) in [("A 1", "Ace: 1 point"), ("J 11", "Jack: 11 points"), ("Q 12", "Queen: 12 points"),
                             ("K♠♣ 13", "Black King (♠K, ♣K): 13 points"), ("K♥♦ \u{2212}1", "Red King (♥K, ♦K): −1 point"),
                             ("Joker 0", "Joker: 0 points")] {
            #expect(sheet.contains(card), "sheet is missing \(card)")
            #expect(rules.contains(rule), "rules changed: \(rule)")
        }
        for (power, rule) in [("7–8 peek yours", "7 or 8, peek own"), ("9–10 peek theirs", "9 or 10, peek opponent"),
                              ("J/Q blind swap", "Jack or Queen, blind switch"), ("K♠♣ look, then swap", "Black King, look and switch")] {
            #expect(sheet.contains(power), "sheet is missing \(power)")
            #expect(rules.contains(rule), "rules changed: \(rule)")
        }
        #expect(sheet.contains("Lowest \u{2212}10") && rules.contains("scores −10 flat"))
        #expect(sheet.contains("your hand + 10") && rules.contains("hand value + 10"))
    }

    @Test("Stays open through same-round updates, closes on the next round or Scores")
    func openState() throws {
        let defaults = try defaults()
        let game = "00000000-0000-4000-8000-000000000001"
        #expect(!content(round: 6).showsRules(gameID: game, defaults: defaults))

        LiveRules.setOpen(true, gameID: game, round: 6, defaults: defaults)
        // A broadcast or the heartbeat (no flag) for the same round: still open.
        #expect(content(round: 6).showsRules(gameID: game, defaults: defaults))
        // Another game, the next round, or a finished game: standings.
        #expect(!content(round: 6).showsRules(gameID: "00000000-0000-4000-8000-000000000002", defaults: defaults))
        #expect(!content(round: 7).showsRules(gameID: game, defaults: defaults))
        #expect(!content(round: 6, phase: .finished).showsRules(gameID: game, defaults: defaults))
        // The button's own update wins over what's saved.
        #expect(!content(round: 6, showsRules: false).showsRules(gameID: game, defaults: defaults))

        LiveRules.setOpen(false, gameID: game, round: 6, defaults: defaults)
        #expect(!content(round: 6).showsRules(gameID: game, defaults: defaults))
        #expect(content(round: 6, showsRules: true).showsRules(gameID: game, defaults: defaults))
    }

    @Test("The flag never reaches the JSON unless set (servers don't send it)")
    func contentJSON() throws {
        let plain = try String(decoding: JSONEncoder().encode(content(round: 6)), as: UTF8.self)
        #expect(!plain.contains("showsRules"))
        let decoded = try JSONDecoder().decode(LiveGameAttributes.ContentState.self, from: Data(plain.utf8))
        #expect(decoded.showsRules == nil)
        let open = try JSONEncoder().encode(content(round: 6, showsRules: true))
        #expect(try JSONDecoder().decode(LiveGameAttributes.ContentState.self, from: open).showsRules == true)
    }
}
