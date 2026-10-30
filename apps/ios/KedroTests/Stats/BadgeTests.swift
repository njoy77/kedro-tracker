import Foundation
import Testing
@testable import Kedro

@Suite("Badges (design §12.6)")
struct BadgeTests {
    private let a = TestPerson.player("A"), b = TestPerson.player("B"), c = TestPerson.player("C")

    private func earned(_ snapshot: StatsSnapshot, _ person: TestPerson, in game: GameID) -> Set<BadgeID> {
        Set(snapshot.badgesEarned[game]?[person.ref]?.map(\.badge) ?? [])
    }

    @Test("Catalog: 33 badges plus Did the Reading, each with a line in every level")
    func catalog() {
        #expect(BadgeDefinition.all.count == 34)
        #expect(BadgeDefinition.all.map(\.id) == BadgeID.allCases)
        #expect(BadgeDefinition.all.count { $0.isSecret } == 3)
        for level in LanguageLevel.allCases {
            let voice = Voice(level: level)
            for badge in BadgeID.allCases {
                #expect(voice.line(badge.copyID) != badge.copyID, "missing \(badge.copyID)")
            }
        }
    }

    @Test("The sample game from scratch: Noah's Ghost Hand and Comeback Kid, Sam's Below Zero")
    func sampleGame() {
        let snapshot = StatsSnapshot.build([PreviewData.sampleState(throughRound: 8, finished: true)])
        let game = PreviewData.sampleGameID
        let noah = Set(snapshot.badgesEarned[game]?[PreviewData.noah.ref]?.map(\.badge) ?? [])
        #expect(noah.isSuperset(of: [.outOfTheGate, .firstBlood, .landedIt, .foundOut, .ghostHand, .comebackKid]))
        let sam = Set(snapshot.badgesEarned[game]?[.guest(PreviewData.samID)]?.map(\.badge) ?? [])
        #expect(sam.contains(.belowZero))
        #expect(sam.contains(.landedIt))
        let ben = Set(snapshot.badgesEarned[game]?[PreviewData.ben.ref]?.map(\.badge) ?? [])
        #expect(ben.contains(.deadHeat))
        #expect(!ben.contains(.firstBlood))
        // Ghost Hand records the round it happened in.
        let ghost = snapshot.record(PreviewData.noah.ref)?.badges[.ghostHand]
        #expect(ghost?.roundNumber == 8)
        #expect(ghost?.tableWord == "Cold Deck")
    }

    @Test("Noah knocked on 0 and landed it: the secret Nothing to See Here, and the Hustler unlocks")
    func secretKnockOnZero() throws {
        let snapshot = StatsSnapshot.build([PreviewData.sampleState(throughRound: 8, finished: true)])
        let record = try #require(snapshot.record(PreviewData.noah.ref))
        #expect(record.badges[.nothingToSeeHere] != nil)
        let avatars = snapshot.availableAvatars(for: PreviewData.noah.ref)
        #expect(avatars.contains(.hustler))
        #expect(!avatars.contains(.ghost))
        #expect(AvatarUnlocks.available(earned: []).count == CuratedAvatarID.allCases.count - 2)
    }

    @Test("Knocking badges: Hat Trick, Bold Choice, Steady Hand across games")
    func knocking() {
        var history = StatsHistory()
        let hatTrick = history.game([a, b, c], [([0, 5, 5], 0), ([1, 5, 5], 0), ([2, 5, 5], 0)])
        let bold = history.game([a, b, c], [([12, 3, 5], 0)])
        // 10 landed in a row starts after the failed knock.
        var steadyGame: GameID?
        for _ in 0..<4 {
            steadyGame = history.game([a, b, c], [([0, 5, 5], 0), ([0, 5, 5], 0), ([0, 5, 5], 0)])
        }
        let snapshot = history.snapshot()
        #expect(earned(snapshot, a, in: hatTrick).contains(.hatTrick))
        #expect(earned(snapshot, a, in: bold).isSuperset(of: [.foundOut, .boldChoice]))
        let steady = snapshot.record(a.ref)?.badges[.steadyHand]
        #expect(steady != nil)
        // 3 + 3 + 3 = 9 after the fail; the 10th lands in the 4th game, round 1.
        #expect(steady?.roundNumber == 1)
        #expect(steady?.gameID == steadyGame)
    }

    @Test("Card badges: Royal Pair at −2, Fat Stack at 40")
    func cards() {
        var history = StatsHistory()
        let game = history.game([a, b, c], [([-2, 40, 5], 0)])
        let snapshot = history.snapshot()
        #expect(earned(snapshot, a, in: game).isSuperset(of: [.royalPair, .belowZero, .landedIt]))
        #expect(earned(snapshot, b, in: game).contains(.fatStack))
        #expect(CardInference.redKings(inHand: -2) == 2)
        #expect(CardInference.redKings(inHand: -1) == 1)
        #expect(CardInference.redKings(inHand: 3) == 0)
    }

    @Test("Streaks: Three-Peat at 3, Untouchable at 5")
    func streaks() throws {
        var history = StatsHistory()
        var games: [GameID] = []
        for _ in 0..<Ratings.rankedAfterGames { games.append(history.win([a, b, c], winner: 0)) }
        let snapshot = history.snapshot()
        #expect(earned(snapshot, a, in: games[2]).contains(.threePeat))
        #expect(!earned(snapshot, a, in: games[1]).contains(.threePeat))
        #expect(earned(snapshot, a, in: games[4]).contains(.untouchable))
        // On the Board comes with the ranking game, not before.
        #expect(!earned(snapshot, a, in: games[4]).contains(.onTheBoard))
        #expect(earned(snapshot, a, in: games[Ratings.rankedAfterGames - 1]).contains(.onTheBoard))
        // Untouchable unlocks its title.
        #expect(snapshot.earnedTitles(of: a.ref).contains(.untouchable))
    }

    @Test("Moments: By a Hair, Shared Spoils, Bottled It, Never Trailed")
    func moments() {
        var history = StatsHistory()
        let shared = history.game([a, b, c], [([4, 4, 9], 0)])          // tied knock, A and B share on 4
        // B leads after round 1 (0 vs 5), A wins round 2 big.
        let bottle = history.game([a, b, c], [([5, 0, 9], 1), ([0, 30, 9], 0)])
        let wire = history.game([a, b, c], Array(repeating: ([0, 5, 5], 0), count: 6))
        let snapshot = history.snapshot()
        #expect(earned(snapshot, a, in: shared).contains(.sharedSpoils))
        #expect(earned(snapshot, b, in: shared).contains(.sharedSpoils))
        #expect(earned(snapshot, b, in: bottle).contains(.bottledIt))
        #expect(earned(snapshot, a, in: wire).contains(.neverTrailed))
        #expect(!earned(snapshot, a, in: wire).contains(.byAHair))
        var close = StatsHistory()
        let byOne = close.game([a, b, c], [([3, 4, 9], 2)]) // C fails: A 3, B 4, C 19
        #expect(earned(close.snapshot(), a, in: byOne).contains(.byAHair))
    }

    @Test("Dark Horse: win against a table all rated higher")
    func darkHorse() {
        var history = StatsHistory()
        for _ in 0..<3 { history.ordered([b, c, a]) }  // A sinks
        let upset = history.ordered([a, b, c])
        #expect(earned(history.snapshot(), a, in: upset).contains(.darkHorse))
    }

    @Test("Rivalry: Nemesis Tamed and the secret Exorcism (the Ghost unlocks)")
    func rivalry() {
        var history = StatsHistory()
        history.ordered([b, a, c])
        history.ordered([b, a, c])                // B is A's nemesis
        let tamed = history.ordered([a, b, c])
        history.ordered([a, b, c])
        let exorcism = history.ordered([a, b, c]) // third straight over B
        let snapshot = history.snapshot()
        #expect(earned(snapshot, a, in: tamed).contains(.nemesisTamed))
        #expect(earned(snapshot, a, in: exorcism).contains(.exorcism))
        #expect(snapshot.availableAvatars(for: a.ref).contains(.ghost))
        #expect(snapshot.earnedTitles(of: a.ref).contains(.exorcist))
    }

    @Test("Social badges count accounts only")
    func social() {
        var history = StatsHistory()
        let guests = (0..<12).map { TestPerson.guest("G\($0)") }
        for start in stride(from: 0, to: 12, by: 3) {
            history.win([a] + guests[start..<start + 3], winner: 0)
        }
        #expect(history.snapshot().record(a.ref)?.badges[.playsWellWithOthers] == nil)
        let accounts = (0..<10).map { TestPerson.player("P\($0)") }
        var friendly = StatsHistory()
        for pair in stride(from: 0, to: 10, by: 2) {
            friendly.win([a, accounts[pair], accounts[pair + 1]], winner: 0)
        }
        #expect(friendly.snapshot().record(a.ref)?.badges[.playsWellWithOthers] != nil)
    }

    @Test("Full House: an 8-player game")
    func fullHouse() {
        var history = StatsHistory()
        let people = (0..<8).map { TestPerson.player("P\($0)") }
        let game = history.win(people, winner: 3)
        let snapshot = history.snapshot()
        for person in people {
            #expect(earned(snapshot, person, in: game).contains(.fullHouse))
        }
    }

    @Test("Trash Talker counts at most 3 taunts a game")
    func trashTalker() {
        var history = StatsHistory()
        for _ in 0..<10 {
            history.game([a, b, c], [([0, 5, 5], 0)], taunts: Array(repeating: (from: 0, to: 1), count: 6))
        }
        // 10 games × 3 counted = 30.
        #expect(history.snapshot().record(a.ref)?.tauntsCounted == 30)
        #expect(history.snapshot().record(a.ref)?.badges[.trashTalker] == nil)
        for _ in 0..<7 {
            history.game([a, b, c], [([0, 5, 5], 0)], taunts: Array(repeating: (from: 0, to: nil), count: 3))
        }
        let snapshot = history.snapshot()
        #expect(snapshot.record(a.ref)?.badges[.trashTalker] != nil)
        #expect(snapshot.earnedTitles(of: a.ref).contains(.stirrer))
    }

    @Test("Bad Influence: your guest claims and plays on their own account")
    func badInfluence() {
        var history = StatsHistory()
        let guest = TestPerson.guest("Sam"), account = TestPerson.player("Sam")
        history.win([a, b, guest], winner: 0)
        let own = history.win([account, b, c], winner: 0)
        let claimed = history.snapshot(StatsOptions(aliases: [guest.ref: account.ref]))
        #expect(claimed.record(a.ref)?.badges[.badInfluence]?.gameID == own)
        #expect(claimed.record(b.ref)?.badges[.badInfluence] != nil)
        // Without the claim it's just two different people.
        #expect(history.snapshot().record(a.ref)?.badges[.badInfluence] == nil)
    }

    @Test("Did the Reading comes from Learn, not a table")
    func didTheReading() {
        var history = StatsHistory()
        history.win([a, b, c], winner: 0)
        let snapshot = history.snapshot(StatsOptions(didTheReading: [a.ref]))
        #expect(snapshot.record(a.ref)?.badges[.didTheReading] != nil)
        #expect(snapshot.record(b.ref)?.badges[.didTheReading] == nil)
    }

    @Test("A badge is earned once, in the game that earned it")
    func earnedOnce() {
        var history = StatsHistory()
        for _ in 0..<4 { history.win([a, b, c], winner: 0) }
        let snapshot = history.snapshot()
        let landed = snapshot.games.map { earned(snapshot, a, in: $0.id).contains(.landedIt) }
        #expect(landed == [true, false, false, false])
    }

    @Test("Next up: closest counting badges first, earned ones dropped")
    func nextUp() throws {
        var history = StatsHistory()
        history.win([a, b, c], winner: 0)
        history.win([a, b, c], winner: 0)
        let record = try #require(history.snapshot().record(a.ref))
        let progress = BadgeEvaluator.progress(record)
        #expect(!progress.contains { $0.badge == .firstBlood })
        #expect(progress.first?.badge == .threePeat)
        #expect(progress.first?.label == "2 of 3")
        #expect(StatsLiteral.nextUp(try #require(progress.first)) == "Next up: Three-Peat, 2 of 3.")
    }
}
