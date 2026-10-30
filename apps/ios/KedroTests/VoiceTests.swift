import Foundation
import Testing
@testable import Kedro

@Suite("Voice and copy deck")
struct VoiceTests {
    private let deck = CopyDeck.standard

    @Test("FNV-1a 64 matches the reference vectors")
    func fnv() {
        #expect(FNV1a.hash("") == 0xcbf2_9ce4_8422_2325)
        #expect(FNV1a.hash("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(FNV1a.hash("foobar") == 0x8594_4171_f739_67e8)
    }

    @Test("Variant choice is stable and identical across levels")
    func variants() {
        let seed = VoiceSeed(gameID: PreviewData.sampleGameID, round: 5, key: "knockLanded")
        let index = seed.index(count: 2)
        #expect(seed.index(count: 2) == index)
        let args: VoiceArgs = ["knocker": "Noah", "hand": 2]
        let clean = Voice(level: .clean).line(.knockLanded, args, seed: seed)
        let unhinged = Voice(level: .unhinged).line(.knockLanded, args, seed: seed)
        let id = VoiceMoment.knockLanded.variantIDs[index]
        #expect(clean == Voice(level: .clean).line(id, args))
        #expect(unhinged == Voice(level: .unhinged).line(id, args))
        // Different rounds spread across variants.
        let picks = Set((1...40).map { VoiceSeed(gameID: PreviewData.sampleGameID, round: $0, key: "knockLanded").index(count: 2) })
        #expect(picks == [0, 1])
    }

    @Test("Variables substitute, integers use a true minus, unknown ones stay")
    func substitution() {
        let voice = Voice(level: .spicy)
        #expect(voice.line("K-01", ["knocker": "Noah", "hand": 2]) == "Noah knocked on 2 and nobody had shit.")
        #expect(voice.line("K-03", ["hand": -1]) == "Knocked on \u{2212}1. Disgusting. Respect.")
        #expect(Voice.substitute("{a} and {b}", ["a": "x"]) == "x and {b}")
        #expect(Voice(level: .unhinged).line("K-21", ["knocker": "Sam"]) == "Sam knocked. Last turns. Pray, you animals.")
        #expect(voice.line("NOT-AN-ID") == "NOT-AN-ID")
    }

    @Test("Every entry resolves to non-empty text at all three levels")
    func everyEntryResolves() {
        for entry in deck.entries.values {
            for level in LanguageLevel.allCases {
                let text = Voice(level: level).line(entry.id)
                #expect(!text.isEmpty, "\(entry.id) is empty at \(level)")
                #expect(text != entry.id, "\(entry.id) didn't resolve at \(level)")
                #expect(text.filter { $0 == "{" }.count == text.filter { $0 == "}" }.count, "\(entry.id) has unbalanced braces")
            }
        }
    }

    @Test("Every ID in docs/kedro-ios-copy.md is in the deck")
    func coversTheCopyDeck() throws {
        let doc = URL(filePath: #filePath)
            .deletingLastPathComponent() // KedroTests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repo root
            .appending(path: "docs/kedro-ios-copy.md")
        guard let text = try? String(contentsOf: doc, encoding: .utf8) else {
            // The simulator can't always read the host checkout; the explicit list below still runs.
            return
        }
        let pattern = /^\| ([A-Z]{1,2}-\d{2}) \|/.anchorsMatchLineEndings()
        let ids = Set(text.matches(of: pattern).map { String($0.1) }).subtracting(["T-11"]) // T-11 has no string
        #expect(ids.count > 150)
        for id in ids.sorted() {
            // The launch taunts (TT-15 onward) live with Talk's library, not the standard deck.
            #expect(deck[id] != nil || TauntLibrary.entry(id) != nil, "\(id) is missing from CopyDeck")
        }
    }

    @Test("Spot-check deck sections are present", arguments: [
        "O-01", "O-11", "S-02", "J-16", "K-01", "K-23", "K-32", "B-09", "W-12", "G-06", "H-07", "R-06", "L-06",
        "N-09", "F-05", "E-04", "T-13", "TT-14", "RC-06", "D-07", "TI-19", "HS-11", "WR-23", "SN-03", "BG-34",
    ])
    func sectionsPresent(id: String) {
        #expect(deck[id] != nil)
    }

    @Test("Literal keys are identical in every level")
    func literalParity() {
        let literalKeys = deck.entries.keys.filter(CopyDeck.isLiteralKey)
        #expect(literalKeys.count > 40)
        for key in literalKeys {
            let entry = deck[key]
            #expect(entry?.isLiteral == true, "\(key) differs between levels")
        }
        #expect(deck["D-06"]?.isLiteral == true)
        #expect(deck["D-07"]?.isLiteral == true)
    }

    @Test("Literal helpers")
    func literals() {
        #expect(Literal.recordRound(6) == "Record Round 6")
        #expect(Literal.fact(round: 5, knocker: "Noah", hand: 2) == "Round 5. Noah knocked on 2.")
        #expect(Literal.verdict(.landed, hand: 2) == "Landed: \u{2212}10.")
        #expect(Literal.verdict(.failed, hand: 2) == "Failed: 2 + 10 = 12.")
        #expect(Literal.knockerDelta(.tied, hand: 5) == "tied · 5")
        #expect(Literal.knockerDelta(.failed, hand: 2) == "failed · 2 + 10")
        #expect(Literal.roundOf(6, 8) == "ROUND 6 OF 8")
        #expect(Literal.deals(word: "Cold Deck", dealer: "Noah") == "COLD DECK · NOAH DEALS")
        #expect(Literal.miniBar(word: "Cold Deck", round: 6, total: 8, rank: Rank(position: 1, isShared: false), score: 26)
            == "COLD DECK · R6/8 · You 1st · 26")
    }

    @Test("Copy rules: banned terms never appear; Clean never swears or goes cute")
    func bannedTerms() throws {
        // Copy deck rule 2: gendered insults and disability/mental-illness slurs, in every level.
        let bannedEverywhere = ["bitch", "pussy", "man up", "retard", "psycho", "spaz"]
        // TODO(talk/moderation): the slur list is owned by Core/Moderation; it is deliberately not
        // spelled out in source. Add hashed or external terms there and lint them here.
        let slurPlaceholders: [String] = []
        // Rule 8: Clean is not cute.
        let cleanSoftened = ["heck", "darn", "frick", "f***", "so-and-so", "buddy", "champ", "yikes", "oopsie"]
        // Clean has zero swearing.
        let profanity = ["fuck", "fucking", "shit", "shitty", "ass", "asshole", "bastard", "damn", "goddamn", "hell", "dick", "dickhead", "dumbass", "crap", "shat"]

        func pattern(_ words: [String]) throws -> NSRegularExpression {
            let alternatives = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            return try NSRegularExpression(pattern: "(?<![a-z])(\(alternatives))(?![a-z])", options: [.caseInsensitive])
        }
        let everywhere = try pattern(bannedEverywhere + slurPlaceholders)
        let cleanOnly = try pattern(cleanSoftened + profanity)

        func match(_ regex: NSRegularExpression, in text: String) -> String? {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap { Range($0.range, in: text) }.map { String(text[$0]) }
        }

        for entry in deck.entries.values {
            for level in LanguageLevel.allCases {
                let text = entry.text(for: level)
                let hit = match(everywhere, in: text)
                #expect(hit == nil, "\(entry.id) (\(level)) contains \(hit ?? "")")
                // Rule 9: no exclamation marks.
                #expect(!text.contains("!"), "\(entry.id) (\(level)) has an exclamation mark")
            }
            // O-08/O-09 are the Spicy and Unhinged sample lines on the level picker, shown verbatim.
            guard !["O-08", "O-09"].contains(entry.id) else { continue }
            let cleanHit = match(cleanOnly, in: entry.clean)
            #expect(cleanHit == nil, "\(entry.id) Clean contains \(cleanHit ?? "")")
        }
    }

    @Test("Spicy and Unhinged actually swear somewhere")
    func levelsDiffer() {
        let spicy = deck.entries.values.filter { $0.spicy != $0.clean }.count
        let unhinged = deck.entries.values.filter { $0.unhinged != $0.clean }.count
        #expect(spicy > 20)
        #expect(unhinged > spicy)
    }

    @Test("Glance strings fit in 60 characters", arguments: ["N-01", "N-02", "N-03", "N-04", "N-05", "N-06", "N-07", "N-08", "N-09", "K-23", "F-01", "F-02"])
    func glanceLength(id: String) {
        // Longest realistic values (copy deck §21).
        let args: VoiceArgs = [
            "host": "Maximilian", "name": "Maximilian", "word": "Corner Booth", "rating": 1086, "badge": "Plays Well With Others",
            "r": 10, "time": "11:46 PM", "year": 2026, "knocker": "Maximilian", "n": 8,
        ]
        for level in LanguageLevel.allCases {
            let text = Voice(level: level).line(id, args)
            #expect(text.count <= 60, "\(id) (\(level)) is \(text.count) characters: \(text)")
        }
    }
}
