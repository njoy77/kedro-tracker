import Foundation

/// The canonical Cambio ruleset (PRD §2) plus how Kedro handles the table (PRD §4), as the
/// searchable Rules reference shows it. Rule text is literal: identical in every language level.
nonisolated struct RuleSection: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var rules: [Rule]
}

nonisolated struct Rule: Hashable, Sendable, Identifiable {
    var id: String
    var text: String
    /// Extra words to match in search ("negative", "minus" for the red King…).
    var keywords: [String] = []

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return text.lowercased().contains(needle) || keywords.contains { $0.contains(needle) }
    }
}

nonisolated enum RulesContent {
    static let sections: [RuleSection] = [
        RuleSection(id: "setup", title: "Setup and Objective", rules: [
            Rule(id: "setup.deal", text: "Each player is dealt 4 cards face down in a 2×2 grid.", keywords: ["grid", "four"]),
            Rule(id: "setup.look", text: "You may not look at your own cards unless a power card lets you.", keywords: ["peek"]),
            Rule(id: "setup.goal", text: "Finish the game with the lowest cumulative score.", keywords: ["win", "objective", "lowest"]),
        ]),
        RuleSection(id: "values", title: "Card Values", rules: [
            Rule(id: "values.ace", text: "Ace: 1 point.", keywords: ["a"]),
            Rule(id: "values.numbers", text: "2–10: face value.", keywords: ["number"]),
            Rule(id: "values.jack", text: "Jack: 11 points.", keywords: ["j"]),
            Rule(id: "values.queen", text: "Queen: 12 points.", keywords: ["q"]),
            Rule(id: "values.blackKing", text: "Black King (♠K, ♣K): 13 points.", keywords: ["k", "spades", "clubs"]),
            Rule(id: "values.redKing", text: "Red King (♥K, ♦K): −1 point.", keywords: ["negative", "minus", "hearts", "diamonds", "k"]),
            Rule(id: "values.joker", text: "Joker: 0 points.", keywords: ["zero"]),
            Rule(id: "values.hand", text: "Your hand value is the sum of your remaining cards when the round ends.", keywords: ["total", "sum"]),
        ]),
        RuleSection(id: "powers", title: "Power Cards", rules: [
            Rule(id: "powers.78", text: "7 or 8, peek own: look at one of your own face-down cards.", keywords: ["seven", "eight", "peek"]),
            Rule(id: "powers.910", text: "9 or 10, peek opponent: look at one of an opponent's face-down cards.", keywords: ["nine", "ten", "peek"]),
            Rule(id: "powers.jq", text: "Jack or Queen, blind switch: swap one of your cards with an opponent's without looking.", keywords: ["swap", "switch"]),
            Rule(id: "powers.blackKing", text: "Black King, look and switch: look at any card, then optionally swap it.", keywords: ["swap", "king"]),
        ]),
        RuleSection(id: "sticking", title: "Sticking", rules: [
            Rule(id: "sticking.match", text: "When a card is discarded, any player may immediately play a matching card from their grid to get rid of it.", keywords: ["stick", "match", "slap"]),
            Rule(id: "sticking.wrong", text: "A wrong stick is handled at the table under the physical rules. It shows up in that player's hand value; Kedro doesn't track it separately.", keywords: ["penalty", "wrong"]),
        ]),
        RuleSection(id: "knocking", title: "Knocking and Round End", rules: [
            Rule(id: "knocking.knock", text: "On their turn, one player may knock to end the round. Knocking is a gamble, not a win or a loss in itself.", keywords: ["knock"]),
            Rule(id: "knocking.lastTurns", text: "After a knock, every other player gets exactly one more turn.", keywords: ["turn"]),
            Rule(id: "knocking.reveal", text: "All cards are revealed and each player's hand value is totaled.", keywords: ["reveal"]),
            Rule(id: "knocking.one", text: "Every round ends with exactly one knock. A round can't be recorded without a knocker.", keywords: ["knocker"]),
        ]),
        RuleSection(id: "scoring", title: "Round Scoring", rules: [
            Rule(id: "scoring.landed", text: "Knocker has the strictly lowest hand: the knock landed. The knocker scores −10 flat, whatever their hand.", keywords: ["landed", "minus 10", "-10", "lowest"]),
            Rule(id: "scoring.tied", text: "Knocker ties for the lowest hand: the knock tied. The knocker scores their hand value.", keywords: ["tie", "tied", "equal"]),
            Rule(id: "scoring.failed", text: "Someone has a lower hand than the knocker: the knock failed. The knocker scores their hand value + 10.", keywords: ["failed", "penalty", "+10", "plus 10"]),
            Rule(id: "scoring.others", text: "Everyone else always scores their own hand value.", keywords: ["others"]),
            Rule(id: "scoring.example1", text: "Example: A knocks. A 4, B 7, C 9. A scores −10, B 7, C 9.", keywords: ["example"]),
            Rule(id: "scoring.example2", text: "Example: A knocks. A 4, B 4, C 9. A scores 4, B 4, C 9.", keywords: ["example"]),
            Rule(id: "scoring.example3", text: "Example: A knocks. A 6, B 3, C 9. A scores 16, B 3, C 9.", keywords: ["example"]),
            Rule(id: "scoring.auto", text: "Kedro applies these automatically from the hands and the knocker. Nobody does the math.", keywords: ["automatic"]),
        ]),
        RuleSection(id: "end", title: "Game End and Winner", rules: [
            Rule(id: "end.planned", text: "Each game has a planned number of rounds. It ends when they're done.", keywords: ["rounds"]),
            Rule(id: "end.extend", text: "Any player can extend the planned rounds or end the game early. Both are logged.", keywords: ["extend", "early"]),
            Rule(id: "end.winner", text: "The winner has the lowest cumulative score. Ties share the win, and every tied player gets credit in all stats.", keywords: ["tie", "win"]),
        ]),
        RuleSection(id: "kedro", title: "At a Kedro Table", rules: [
            Rule(id: "kedro.size", text: "A table holds 3 to 8 players.", keywords: ["players", "seats"]),
            Rule(id: "kedro.deal", text: "Seats go clockwise around the table. The deal passes one seat to the left after every round. Anyone can correct the dealer; it's logged.", keywords: ["dealer", "deal"]),
            Rule(id: "kedro.modes", text: "Scorekeeper: one person enters every hand. Everyone reports: each player enters their own hand, and someone reports for guests without the app.", keywords: ["scorekeeper", "self-report", "mode"]),
            Rule(id: "kedro.edits", text: "Anyone at the table can fix any round while the game is on. Every change is on the record for everyone.", keywords: ["edit", "fix", "correction", "audit"]),
            Rule(id: "kedro.finished", text: "A finished game is permanent. Nobody can change it.", keywords: ["finished", "locked"]),
            Rule(id: "kedro.abandon", text: "Ending early counts in stats. Abandoning voids the game: it stays in history, marked, and counts for nothing.", keywords: ["abandon", "void"]),
            Rule(id: "kedro.seats", text: "Seats are fixed after Round 1. Anyone arriving later watches and is in the rematch.", keywords: ["watch", "late"]),
        ]),
    ]

    /// Sections with only the rules matching `query` (all of them when it's empty).
    static func search(_ query: String) -> [RuleSection] {
        sections.compactMap { section in
            let titleMatches = section.title.lowercased().contains(query.trimmingCharacters(in: .whitespaces).lowercased())
            let rules = titleMatches && !query.isEmpty ? section.rules : section.rules.filter { $0.matches(query) }
            return rules.isEmpty ? nil : RuleSection(id: section.id, title: section.title, rules: rules)
        }
    }
}
