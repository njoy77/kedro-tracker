import Foundation
import Testing
@testable import Kedro

/// The Live Activity truncation rule (design §13.2): in the top 5, ranks 1–5; otherwise ranks
/// 1–4, `···`, then your row with your true rank.
@Suite("Live Activity truncation")
struct LiveStandingsLayoutTests {
    private func rows(_ count: Int, me: Int? = nil, rankLabels: [String]? = nil) -> [LiveStandingRow] {
        (0..<count).map { index in
            LiveStandingRow(
                id: "p:\(index)",
                name: "P\(index)",
                rankLabel: rankLabels?[index] ?? "\(index + 1)",
                ordinal: "\(index + 1)th",
                score: "\(index * 5)",
                delta: "+\(index)",
                outcome: nil,
                isMe: index == me,
                isLeader: index == 0,
                isDealer: false,
                avatar: .initial(letter: "P", isGuest: false)
            )
        }
    }

    private func ids(_ slots: [LiveRowSlot]) -> [String] {
        slots.map { $0.row?.id ?? "···" }
    }

    @Test("Five or fewer seats show everyone")
    func smallTable() {
        #expect(ids(LiveStandingsLayout.lockScreen(rows(3, me: 2))) == ["p:0", "p:1", "p:2"])
        #expect(ids(LiveStandingsLayout.lockScreen(rows(5, me: 4))) == ["p:0", "p:1", "p:2", "p:3", "p:4"])
    }

    @Test("In the top 5 of a big table: ranks 1–5", arguments: 0..<5)
    func inTopFive(me: Int) {
        let slots = LiveStandingsLayout.lockScreen(rows(8, me: me))
        #expect(ids(slots) == ["p:0", "p:1", "p:2", "p:3", "p:4"])
        #expect(slots.contains { $0.row?.isMe == true })
    }

    @Test("Outside the top 5: ranks 1–4, ···, then you with your true rank", arguments: 5..<8)
    func outsideTopFive(me: Int) throws {
        let slots = LiveStandingsLayout.lockScreen(rows(8, me: me))
        #expect(ids(slots) == ["p:0", "p:1", "p:2", "p:3", "···", "p:\(me)"])
        let mine = try #require(slots.last?.row)
        #expect(mine.isMe)
        #expect(mine.rankLabel == "\(me + 1)")
        #expect(slots.count == LiveStandingsLayout.lockScreenLimit + 1)
        #expect(slots.compactMap(\.row).count == LiveStandingsLayout.lockScreenLimit)
    }

    @Test("Watchers see ranks 1–5")
    func watcher() {
        #expect(ids(LiveStandingsLayout.lockScreen(rows(8))) == ["p:0", "p:1", "p:2", "p:3", "p:4"])
    }

    @Test("Shared ranks don't stretch the list: positions decide")
    func sharedRanks() {
        let labels = ["1", "2=", "2=", "2=", "2=", "2=", "7", "8"]
        let slots = LiveStandingsLayout.lockScreen(rows(8, me: 5, rankLabels: labels))
        #expect(ids(slots) == ["p:0", "p:1", "p:2", "p:3", "···", "p:5"])
        #expect(slots.last?.row?.rankLabel == "2=")
    }

    @Test("Expanded Island: top 3 plus you")
    func expanded() {
        #expect(ids(LiveStandingsLayout.expanded(rows(8, me: 1))) == ["p:0", "p:1", "p:2"])
        #expect(ids(LiveStandingsLayout.expanded(rows(8, me: 3))) == ["p:0", "p:1", "p:2", "p:3"])
        #expect(ids(LiveStandingsLayout.expanded(rows(8, me: 6))) == ["p:0", "p:1", "p:2", "···", "p:6"])
        #expect(ids(LiveStandingsLayout.expanded(rows(2, me: 1))) == ["p:0", "p:1"])
    }

    @Test("Slot IDs are unique (ForEach)")
    func uniqueIDs() {
        let slots = LiveStandingsLayout.lockScreen(rows(8, me: 7))
        #expect(Set(slots.map(\.id)).count == slots.count)
    }
}
