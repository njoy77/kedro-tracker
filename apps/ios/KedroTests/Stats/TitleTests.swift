import Foundation
import Testing
@testable import Kedro

@Suite("Titles (design §12.7)")
struct TitleTests {
    private let people = ["A", "B", "C", "D", "E", "F"].map { TestPerson.player($0) }
    private var a: TestPerson { people[0] }
    private var b: TestPerson { people[1] }

    /// One-round games where `knocker` knocks on 0 against 5s (landed), or on 9 into a 0 (failed).
    private func knock(_ history: inout StatsHistory, by knocker: Int, lands: Bool = true) {
        var hands = Array(repeating: 5, count: people.count)
        if lands {
            hands[knocker] = 0
        } else {
            hands[knocker] = 9
            hands[(knocker + 1) % people.count] = 0
        }
        history.game(people, [(hands, knocker)])
    }

    @Test("Every title has a name and tagline in every level")
    func catalog() {
        #expect(TitleID.allCases.count == 18)
        for level in LanguageLevel.allCases {
            let voice = Voice(level: level)
            for title in TitleID.allCases {
                #expect(voice.line(title.copyID) != title.copyID)
                #expect(voice.line(title.taglineID) != title.taglineID)
            }
        }
        #expect(Voice(level: .spicy).line(TitleID.stirrer.copyID) == "Shit-Stirrer")
        #expect(Voice(level: .clean).line(TitleID.stirrer.copyID) == "The Stirrer")
    }

    @Test("The Closer: needs 15 knocks, ties go to whoever got there first, and it moves")
    func closerTransfer() {
        var history = StatsHistory()
        for _ in 0..<16 { knock(&history, by: 0) }
        let aOnly = history.snapshot()
        #expect(aOnly.holder(of: .closer, amongPeopleOf: a.ref) == a.ref)
        #expect(aOnly.heldTitles(of: a.ref).contains(.closer))

        for _ in 0..<16 { knock(&history, by: 1) }
        let tied = history.snapshot()
        // Both at 100%: A got there first.
        #expect(tied.holder(of: .closer, amongPeopleOf: b.ref) == a.ref)

        knock(&history, by: 0, lands: false)
        let moved = history.snapshot()
        #expect(moved.holder(of: .closer, amongPeopleOf: a.ref) == b.ref)
        let lost = moved.titlesLost(by: a.ref, since: tied)
        #expect(lost.contains { $0.title == .closer && $0.takenBy == b.ref })
        // A displayed The Closer: it quietly falls back to their best earned title.
        #expect(moved.displayTitle(for: a.ref, chosen: TitleID.closer.rawValue) == moved.bestEarnedTitle(of: a.ref))
        #expect(moved.displayTitle(for: b.ref, chosen: TitleID.closer.rawValue) == .closer)
    }

    @Test("Held titles need 5 ranked people and their own minimums")
    func minimums() {
        var small = StatsHistory()
        let four = Array(people.prefix(4))
        for _ in 0..<20 { small.game(four, [([0, 5, 5, 5], 0)]) }
        let tooFew = small.snapshot()
        #expect(tooFew.holder(of: .topDog, amongPeopleOf: four[0].ref) == nil)
        #expect(tooFew.holder(of: .closer, amongPeopleOf: four[0].ref) == nil)

        var history = StatsHistory()
        for _ in 0..<20 { knock(&history, by: 0) }
        let snapshot = history.snapshot()
        #expect(snapshot.holder(of: .topDog, amongPeopleOf: a.ref) == a.ref)
        // 20 rounds is short of Knock Merchant's 50.
        #expect(snapshot.holder(of: .knockMerchant, amongPeopleOf: a.ref) == nil)
        // The Accountant needs 20 games: A has exactly 20, and the lowest average round.
        #expect(snapshot.holder(of: .accountant, amongPeopleOf: a.ref) == a.ref)
    }

    @Test("Earned titles: Fresh Meat for everyone, the rest from badges; nobody is forced")
    func earned() {
        var history = StatsHistory()
        knock(&history, by: 0)
        let snapshot = history.snapshot()
        // Knocking on 0 is a Ghost Hand, which unlocks The Ghost.
        #expect(snapshot.earnedTitles(of: a.ref) == [.freshMeat, .theGhost])
        #expect(snapshot.earnedTitles(of: b.ref) == [.freshMeat])
        #expect(snapshot.displayTitle(for: a.ref, chosen: nil) == nil)
        #expect(snapshot.displayTitle(for: a.ref, chosen: TitleID.freshMeat.rawValue) == .freshMeat)
        // A title you don't have shows nothing.
        #expect(snapshot.displayTitle(for: a.ref, chosen: TitleID.royalty.rawValue) == nil)
        #expect(snapshot.displayTitle(for: a.ref, chosen: "nonsense") == nil)
    }

    @Test("Game end recalculates the titles at the table")
    func gameEndTitles() throws {
        var history = StatsHistory()
        for _ in 0..<16 { knock(&history, by: 0) }
        let last = try #require(history.states.last?.gameID)
        let snapshot = history.snapshot()
        let progression = try #require(snapshot.gameEnd(for: last, viewer: a.ref, chosenTitles: [a.ref: TitleID.closer.rawValue]))
        #expect(progression.titles[a.ref] == .closer)
        #expect(progression.titles[b.ref] == nil)
    }
}
