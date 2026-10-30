import Foundation
import Testing
@testable import Kedro

@Suite("Taunt filter")
struct TauntFilterTests {
    /// Stand-in blocked terms. The real list ships hashed in TauntBlocklist.json and is never
    /// spelled out in source; these made-up words exercise the same matching.
    private let filter = TauntFilter(blocklist: TauntBlocklist(
        version: 1,
        blockedSHA256: [TauntBlocklist.hash("zorblax"), TauntBlocklist.hash("vexmoor"), TauntBlocklist.hash("grimbletoad")],
        profanityStems: ["fuck", "shit"],
        profanityWords: ["ass", "damn", "hell"]
    ))

    @Test("Blocks a listed term", arguments: [
        "you absolute zorblax",
        "ZORBLAX",
        "Zörblax.",
        "z0rbl4x",
        "zorbl@x",
        "zorrrrblaxxx",
        "zorblaxes",
        "zorblaxing all night",
        "z o r b l a x",
        "z.o.r.b.l.a.x",
        "grimble toad",
        "vex-moor",
    ])
    func blocks(text: String) {
        #expect(filter.check(text) == .blocked, "\(text)")
    }

    @Test("Allows profanity and ordinary words", arguments: [
        "Knocking on that? Brave as shit.",
        "you smug bastard",
        "if sam lands this i'm moving to another country",
        "zorb is not the term",
        "assume the worst",
        "Nice!",
        "",
    ])
    func allows(text: String) {
        #expect(filter.check(text) == .allowed, "\(text)")
    }

    @Test("An empty list blocks nothing")
    func emptyList() {
        #expect(TauntFilter(blocklist: .empty).check("zorblax") == .allowed)
    }

    @Test("The bundled list loads")
    func bundled() {
        let list = TauntBlocklist.bundled(.main)
        #expect(list.version >= 1)
        #expect(!list.blockedSHA256.isEmpty)
        #expect(list.blockedSHA256.allSatisfy { $0.count == 64 })
        #expect(!list.profanityWords.isEmpty)
    }

    @Test("Clean viewers see profanity masked; everything else as written")
    func masking() {
        #expect(filter.maskingProfanity(in: "Brave as shit.") == "Brave as s***.")
        #expect(filter.maskingProfanity(in: "Fucking hell, Ana") == "F****** h***, Ana")
        #expect(filter.maskingProfanity(in: "sh!t knock") == "s*** knock")
        #expect(filter.maskingProfanity(in: "assume the hello") == "assume the hello")
        #expect(filter.maskingProfanity(in: "No notes.") == "No notes.")
        #expect(filter.containsProfanity("damn"))
        #expect(!filter.containsProfanity("dam"))
    }

    @Test("Normalization folds case, accents and look-alikes")
    func normalization() {
        #expect(TauntFilter.normalizedToken("ZÖRB1@X") == "zorbiax")
        #expect(TauntFilter.collapsingRepeats("fuuuuck") == "fuck")
        #expect(TauntFilter.collapsingRepeats("hell") == "hell")
    }
}
