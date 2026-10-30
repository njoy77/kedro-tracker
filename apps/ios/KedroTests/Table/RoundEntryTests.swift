import Foundation
import Testing
@testable import Kedro

/// The Round sheet's state machine (design §7.1–§7.3, §9.2), driven against the §17 sample game.
@Suite("Round entry")
struct RoundEntryTests {
    private let seats = PreviewData.sampleSeats.map(\.id)
    private var noah: SeatID { PreviewData.noahSeat }
    private var ana: SeatID { PreviewData.anaSeat }
    private var ben: SeatID { PreviewData.benSeat }
    private var cleo: SeatID { PreviewData.cleoSeat }
    private var sam: SeatID { PreviewData.samSeat }

    private func type(_ digits: String, into entry: inout RoundEntry) {
        for character in digits {
            if character == "-" {
                entry.press(.minus)
            } else if let digit = character.wholeNumberValue {
                entry.press(.digit(digit))
            }
        }
    }

    @Test("Recording Round 6: knocker first, Next through the rows, then Save")
    func recordsRoundSix() throws {
        var entry = RoundEntry(roundNumber: 6, seats: seats)
        #expect(entry.focus == noah)
        #expect(entry.rows == seats)
        #expect(!entry.canSave)

        entry.selectKnocker(sam)
        #expect(entry.rows == [sam, noah, ana, ben, cleo])
        #expect(entry.focus == sam, "Nothing typed yet, so focus jumps to the knocker")

        type("1", into: &entry)
        #expect(entry.primaryAction == .next(noah))
        entry.advance()
        type("7", into: &entry)
        #expect(entry.verdict == .leading(knocker: sam, hand: 1))
        #expect(entry.previewScore(sam) == -10)
        #expect(entry.previewScore(noah) == 7)
        for (seat, digits) in [(ana, "2"), (ben, "9"), (cleo, "8")] {
            entry.advance()
            #expect(entry.focus == seat)
            type(digits, into: &entry)
        }
        #expect(entry.primaryAction == .save)
        #expect(entry.canSave)
        #expect(entry.verdict == .landed(knocker: sam, hand: 1))
        let round = try #require(entry.round)
        #expect(round == PreviewData.sampleRounds[5])
    }

    @Test("Save stays disabled until a knocker is picked")
    func needsKnocker() {
        var entry = RoundEntry(roundNumber: 1, seats: seats)
        for digits in ["9", "3", "12", "7", "15"] {
            type(digits, into: &entry)
            entry.advance()
        }
        #expect(entry.isComplete)
        #expect(entry.primaryAction == .save)
        #expect(!entry.canSave)
        entry.selectKnocker(ana)
        #expect(entry.canSave)
        #expect(entry.focus != ana, "Values are typed, so picking the knocker doesn't move focus")
        entry.selectKnocker(ana)
        #expect(entry.knocker == nil, "Tapping the knocker again clears it")
    }

    @Test("A live knock pre-fills the knocker, but never overrides a pick")
    func liveKnockPrefill() {
        let mark = LiveKnock(roundNumber: 6, knocker: sam, markedBy: ana, markedByName: "Ana", markedAt: .now, opId: UUID())
        let entry = RoundEntry(roundNumber: 6, seats: seats, liveKnock: mark)
        #expect(entry.knocker == sam)
        #expect(entry.knockerSource == .liveKnock(markedBy: "Ana"))
        #expect(entry.focus == sam)

        var picked = RoundEntry(roundNumber: 6, seats: seats)
        picked.selectKnocker(noah)
        picked.applyLiveKnock(mark)
        #expect(picked.knocker == noah)

        var open = RoundEntry(roundNumber: 6, seats: seats)
        open.applyLiveKnock(LiveKnock(roundNumber: 5, knocker: sam, markedBy: ana, markedByName: "Ana", markedAt: .now, opId: UUID()))
        #expect(open.knocker == nil, "A mark for another round is ignored")
        open.applyLiveKnock(mark)
        #expect(open.knocker == sam)
    }

    @Test("A failed knock resolves as soon as anyone is lower; a tie waits for every value")
    func verdicts() {
        var failed = RoundEntry(roundNumber: 3, seats: seats)
        failed.selectKnocker(noah)
        type("8", into: &failed)
        failed.advance()
        type("3", into: &failed)
        #expect(failed.verdict == .failed(knocker: noah, hand: 8, by: ana, low: 3))
        #expect(failed.previewScore(noah) == 18)
        #expect(failed.verdict?.isFinal == true)

        var tied = RoundEntry(roundNumber: 2, seats: seats)
        tied.selectKnocker(ben)
        type("5", into: &tied)
        for digits in ["6", "11", "5"] {
            tied.advance()
            type(digits, into: &tied)
        }
        #expect(tied.verdict == .tiedSoFar(knocker: ben, hand: 5, with: cleo))
        tied.advance()
        type("20", into: &tied)
        #expect(tied.verdict == .tied(knocker: ben, hand: 5, with: cleo))
        #expect(tied.previewScore(ben) == 5)
    }

    @Test("Tapping a row jumps to it; Next skips filled rows")
    func focusJumps() {
        var entry = RoundEntry(roundNumber: 1, seats: seats)
        entry.setFocus(cleo)
        type("7", into: &entry)
        #expect(entry.primaryAction == .next(sam))
        entry.advance()
        type("15", into: &entry)
        #expect(entry.primaryAction == .next(noah), "Wraps to the first empty row")
    }

    @Test("Corrections start filled; the first keystroke replaces the tapped value")
    func editing() throws {
        let original = PreviewData.sampleRounds[3]
        var entry = RoundEntry(editing: original, seats: seats, focus: sam)
        #expect(entry.isEditing)
        #expect(entry.focus == sam)
        #expect(entry.value(sam) == -1)
        #expect(!entry.hasChanges)
        #expect(entry.primaryAction == .save)

        type("3", into: &entry)
        #expect(entry.value(sam) == 3, "Replaced, not appended")
        #expect(entry.hasChanges)
        type("1", into: &entry)
        #expect(entry.value(sam) == 31, "Later keys append")
        let round = try #require(entry.round)
        #expect(round.knocker == cleo)
        #expect(round.number == 4)

        var cleared = RoundEntry(editing: original, seats: seats, focus: ben)
        cleared.press(.delete)
        #expect(cleared.value(ben) == nil)
        #expect(!cleared.canSave)
    }

    @Test("The typo guard asks once per round, and Fix focuses the row")
    func typoGuardOnce() {
        var entry = RoundEntry(roundNumber: 1, seats: seats)
        entry.selectKnocker(ana)
        for digits in ["3", "9", "52", "7", "15"] {
            type(digits, into: &entry)
            entry.advance()
        }
        #expect(entry.canSave)
        #expect(entry.typoCheck() == TypoGuard.Flag(seat: ben, hand: 52))
        entry.fix(ben)
        #expect(entry.focus == ben)
        type("12", into: &entry)
        #expect(entry.value(ben) == 12)
        #expect(entry.typoCheck() == nil)

        var kept = RoundEntry(roundNumber: 1, seats: seats)
        kept.selectKnocker(ana)
        for digits in ["3", "9", "52", "7", "15"] {
            type(digits, into: &kept)
            kept.advance()
        }
        #expect(kept.typoCheck() != nil)
        #expect(kept.typoCheck() == nil, "Keep 52: never asked twice")
    }

    @Test("Red Kings: negatives are capped by the two in the deck")
    func redKingCap() {
        var accepted: Bool
        var entry = RoundEntry(roundNumber: 1, seats: seats)
        type("-2", into: &entry)
        #expect(entry.value(noah) == -2)
        entry.advance()
        #expect(entry.redKingsLeft(for: ana) == 0)
        accepted = entry.press(.minus)
        #expect(!accepted, "Both red Kings are already in Noah's hand")
        type("4", into: &entry)
        #expect(entry.value(ana) == 4)
    }

    @Test("Card mode adds up cards and disables the red King after two")
    func cardMode() {
        var accepted: Bool
        var entry = RoundEntry(roundNumber: 1, seats: seats)
        accepted = entry.add(.redKing)
        #expect(accepted)
        accepted = entry.add(.three)
        #expect(accepted)
        accepted = entry.add(.seven)
        #expect(accepted)
        #expect(entry.value(noah) == 9)
        #expect(entry.entry(noah).trayText == "K♥ 3 7 = 9")
        #expect(entry.redKingsLeftForFocus == 1)
        accepted = entry.add(.redKing)
        #expect(accepted)
        #expect(entry.redKingsLeftForFocus == 0)
        accepted = entry.add(.redKing)
        #expect(!accepted, "A third red King doesn't exist")
        accepted = entry.removeLastCard()
        #expect(accepted)
        #expect(entry.value(noah) == 9)

        entry.advance()
        #expect(entry.redKingsLeftForFocus == 1, "Noah holds one red King")
    }
}

@Suite("Hand entry")
struct HandEntryTests {
    @Test("The − key toggles the sign; only −1 and −2 are possible")
    func minusKey() {
        var accepted: Bool
        var hand = HandEntry.empty
        accepted = hand.press(.minus, negativeLimit: 2)
        #expect(accepted)
        #expect(hand.display == "−")
        #expect(hand.value == nil)
        accepted = hand.press(.digit(0), negativeLimit: 2)
        #expect(!accepted, "No −0")
        accepted = hand.press(.digit(1), negativeLimit: 2)
        #expect(accepted)
        #expect(hand.value == -1)
        accepted = hand.press(.digit(2), negativeLimit: 2)
        #expect(!accepted, "No −12")
        #expect(hand.value == -1)
        accepted = hand.press(.minus, negativeLimit: 2)
        #expect(accepted)
        #expect(hand.value == 1)
        var capped = HandEntry.empty
        accepted = capped.press(.minus, negativeLimit: 0)
        #expect(!accepted)
    }

    @Test("No upper limit short of 999; three digits at most")
    func noUpperLimit() {
        var accepted: Bool
        var hand = HandEntry.empty
        for digit in [9, 9, 9] {
            accepted = hand.press(.digit(digit), negativeLimit: 2)
            #expect(accepted)
        }
        #expect(hand.value == 999)
        accepted = hand.press(.digit(1), negativeLimit: 2)
        #expect(!accepted)
        #expect(hand.value == 999)

        var big = HandEntry.empty
        _ = big.press(.digit(5), negativeLimit: 2)
        _ = big.press(.digit(2), negativeLimit: 2)
        #expect(big.value == 52, "Hands above 32 are accepted")
    }

    @Test("A leading zero is replaced; delete walks back to empty")
    func zeroAndDelete() {
        var accepted: Bool
        var hand = HandEntry.empty
        _ = hand.press(.digit(0), negativeLimit: 2)
        #expect(hand.value == 0)
        _ = hand.press(.digit(5), negativeLimit: 2)
        #expect(hand.value == 5)
        _ = hand.press(.digit(2), negativeLimit: 2)
        accepted = hand.press(.delete, negativeLimit: 2)
        #expect(accepted)
        #expect(hand.value == 5)
        accepted = hand.press(.delete, negativeLimit: 2)
        #expect(accepted)
        #expect(hand == .empty)
        accepted = hand.press(.delete, negativeLimit: 2)
        #expect(!accepted)
    }

    @Test("Card values follow PRD §2.2")
    func cardValues() {
        #expect(CardFace.ace.value == 1)
        #expect(CardFace.queen.value == 12)
        #expect(CardFace.blackKing.value == 13)
        #expect(CardFace.redKing.value == -1)
        #expect(CardFace.joker.value == 0)
    }
}

@Suite("Typo guard")
struct TypoGuardTests {
    /// Four seats; the array is the seat order.
    private let order = (0..<4).map { _ in PlayerRef.guest(GuestID()).seatID }

    private func hands(_ values: [Int]) -> [SeatID: Int] {
        Dictionary(uniqueKeysWithValues: zip(order, values))
    }

    @Test("≥ 25 and at least double the next-highest hand")
    func doubleRule() {
        #expect(TypoGuard.flag(hands([26, 12, 3, 5]), order: order) == TypoGuard.Flag(seat: order[0], hand: 26))
        #expect(TypoGuard.flag(hands([26, 14, 3, 5]), order: order) == nil)
        #expect(TypoGuard.flag(hands([24, 2, 3, 5]), order: order) == nil, "Under 25 is never questioned")
    }

    @Test("≥ 45 is always questioned")
    func absoluteRule() {
        #expect(TypoGuard.flag(hands([45, 40, 30, 5]), order: order)?.hand == 45)
        #expect(TypoGuard.flag(hands([44, 40, 30, 5]), order: order) == nil)
    }

    @Test("The highest suspicious hand wins; seat order breaks ties")
    func picksOne() {
        #expect(TypoGuard.flag(hands([3, 50, 60, 5]), order: order)?.seat == order[2])
        #expect(TypoGuard.flag(hands([50, 3, 50, 5]), order: order)?.seat == order[0])
    }
}
