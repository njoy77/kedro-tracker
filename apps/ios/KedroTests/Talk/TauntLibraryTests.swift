import Foundation
import Testing
@testable import Kedro

@Suite("Canned taunt library")
struct TauntLibraryTests {
    /// Words that make a line "swear" (copy deck §3), matched as whole words.
    private static let swears = [
        "fuck", "fucking", "fucked", "shit", "shitty", "ass", "asshole", "assholes", "bastard", "damn", "damned", "goddamn",
        "hell", "dick", "dickhead", "dumbass", "crap", "bullshit", "smartass",
    ]
    /// Copy deck rule 2 and rule 8.
    private static let bannedEverywhere = ["bitch", "pussy", "man up", "retard", "psycho", "spaz"]
    private static let cleanSoftened = ["heck", "darn", "frick", "f***", "so-and-so", "buddy", "champ", "yikes", "oopsie"]

    private static func count(_ words: [String], in text: String) -> Int {
        let alternatives = words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: "(?<![a-z])(\(alternatives))(?![a-z])", options: [.caseInsensitive]) else {
            return 0
        }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    @Test("At least 80 taunts, unique IDs, every group stocked")
    func size() {
        #expect(TauntLibrary.all.count >= 80)
        #expect(Set(TauntLibrary.all.map(\.id)).count == TauntLibrary.all.count)
        for group in TauntGroup.allCases {
            #expect(TauntLibrary.all.filter { $0.group == group }.count >= 8, "\(group) is thin")
        }
    }

    @Test("The deck's samples resolve from the copy deck")
    func deckSamples() throws {
        for id in TauntGroup.allCases.flatMap(\.tauntIDs) {
            let taunt = try #require(TauntLibrary.taunt(id))
            #expect(taunt.entry == CopyDeck.standard[id])
            #expect(TauntGroup.allCases.first { $0.tauntIDs.contains(id) } == taunt.group)
        }
    }

    @Test("Copy rules: no banned terms, no exclamation marks, Clean never swears or goes cute")
    func copyRules() {
        for taunt in TauntLibrary.all {
            for level in LanguageLevel.allCases {
                let text = taunt.entry.text(for: level)
                #expect(!text.isEmpty)
                #expect(Self.count(Self.bannedEverywhere, in: text) == 0, "\(taunt.id) \(level): \(text)")
                #expect(!text.contains("!"), "\(taunt.id) \(level) has an exclamation mark")
                #expect(text.count <= 60, "\(taunt.id) \(level) is too long for a toast")
            }
            #expect(Self.count(Self.swears + Self.cleanSoftened, in: taunt.entry.clean) == 0, "\(taunt.id) Clean: \(taunt.entry.clean)")
        }
    }

    @Test("Spicy swears about a third of the time, once per line; Unhinged at least half")
    func density() {
        let total = Double(TauntLibrary.all.count)
        let spicy = TauntLibrary.all.filter { Self.count(Self.swears, in: $0.entry.spicy) > 0 }
        let unhinged = TauntLibrary.all.filter { Self.count(Self.swears, in: $0.entry.unhinged) > 0 }
        let spicyShare = Double(spicy.count) / total
        let unhingedShare = Double(unhinged.count) / total
        #expect((0.25...0.40).contains(spicyShare), "Spicy \(spicyShare)")
        #expect(unhingedShare >= 0.5, "Unhinged \(unhingedShare)")
        for taunt in TauntLibrary.all {
            #expect(Self.count(Self.swears, in: taunt.entry.spicy) <= 1, "\(taunt.id) Spicy swears twice")
        }
    }

    @Test("After a failed knock, Knocks comes first and leads with failed-knock taunts")
    func failedKnockFirst() throws {
        let sections = TauntLibrary.sections(for: TauntContext(moments: [.knockFailed]))
        let first = try #require(sections.first)
        #expect(first.group == .knocks)
        #expect(first.isTimely)
        #expect(first.title == "Knocks · right now")
        #expect(first.taunts.first?.moments.contains(.knockFailed) == true)
        // Taunts for other moments (a live knock, a landed knock) aren't offered.
        #expect(!first.taunts.contains { $0.id == "TT-01" })
        #expect(!sections.contains { $0.group == .leader })
        #expect(sections.contains { $0.group == .general && !$0.isTimely })
    }

    @Test("With nothing going on, only the anytime taunts show")
    func quietTable() {
        let sections = TauntLibrary.sections(for: TauntContext(moments: []))
        #expect(!sections.isEmpty)
        #expect(sections.allSatisfy { !$0.isTimely })
        #expect(sections.flatMap(\.taunts).allSatisfy { $0.moments.isEmpty })
    }

    @Test("The sample table after Round 5: Sam's live knock makes Knocks timely")
    func sampleContext() throws {
        let state = GameState.fold(PreviewData.sampleOperations(throughRound: 5, finished: false, liveKnock: true), gameID: PreviewData.sampleGameID)
        let target = TauntTarget.suggested(for: state, me: PreviewData.noahSeat)
        #expect(target == .seat(PreviewData.samSeat))
        let context = TauntContext(state: state, target: target, sender: PreviewData.noahSeat)
        #expect(context.moments.contains(.liveKnock))
        #expect(!context.moments.contains(.leader)) // Noah leads, not Sam
        #expect(TauntLibrary.sections(for: context).first?.group == .knocks)
    }

    @Test("Never suggests yourself; falls back to the table")
    func suggestedTarget() {
        let state = PreviewData.sampleState(throughRound: 5)
        // Round 5's knocker was Noah: aimed at Noah from anyone else, at the table from Noah.
        #expect(TauntTarget.suggested(for: state, me: PreviewData.anaSeat) == .seat(PreviewData.noahSeat))
        #expect(TauntTarget.suggested(for: state, me: PreviewData.noahSeat) == .table)
    }

    @Test("Canned taunts render in the viewer's level; custom ones as written, masked for Clean")
    func rendering() {
        let canned = TauntContent.canned(id: "TT-01")
        #expect(TauntRendering.text(canned, level: .clean) == "Knocking on that? Brave.")
        #expect(TauntRendering.text(canned, level: .unhinged) == "Knocking on that? Brave as shit.")
        #expect(TauntRendering.text(.canned(id: "TT-999"), level: .clean) == nil)
        let filter = TauntFilter(blocklist: TauntBlocklist(version: 1, blockedSHA256: [], profanityStems: ["shit"], profanityWords: []))
        let custom = TauntContent.custom(text: "holy shit sam")
        #expect(TauntRendering.text(custom, level: .clean, filter: filter) == "holy s*** sam")
        #expect(TauntRendering.text(custom, level: .spicy, filter: filter) == "holy shit sam")
    }
}
