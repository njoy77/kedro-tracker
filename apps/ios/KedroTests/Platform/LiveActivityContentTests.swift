import Foundation
import Testing
@testable import Kedro

/// Live Activity content from the fold (design §13.2), checked against the sample game (§17),
/// and the content-state JSON the backend's broadcast pushes must match.
@Suite("Live Activity content")
struct LiveActivityContentTests {
    private let noah = LiveActivityContent.Viewer(seat: PreviewData.noahSeat, isScorekeeper: true)
    private let sam = LiveActivityContent.Viewer(seat: PreviewData.samSeat, isScorekeeper: false)
    private let voice = Voice(level: .unhinged)
    private let now = Date(timeIntervalSince1970: 1_792_879_560)

    private func content(throughRound round: Int = 5, finished: Bool = false, liveKnock: Bool = false, viewer: LiveActivityContent.Viewer? = nil) throws -> LiveGameAttributes.ContentState {
        let state = GameState.fold(
            PreviewData.sampleOperations(throughRound: round, finished: finished, liveKnock: liveKnock),
            gameID: PreviewData.sampleGameID
        )
        return try #require(LiveActivityContent.contentState(for: state, viewer: viewer ?? noah, voice: voice, now: now))
    }

    @Test("After Round 5: rows best first, Noah's landed knock, Noah deals")
    func afterRoundFive() throws {
        let content = try content()
        #expect(content.phase == .active)
        #expect(content.roundNumber == 6)
        #expect(content.metadataLine == "ROUND 6 OF 6 · NOAH DEALS")
        #expect(content.rows.map(\.name) == ["Noah", "Ana", "Ben", "Cleo", "Sam"])
        #expect(content.rows.map(\.score) == ["26", "29", "44", "45", "47"])
        #expect(content.rows.map(\.delta) == ["\u{2212}10", "+9", "+6", "+11", "+4"])
        #expect(content.rows[0].outcome == .landed)
        #expect(content.rows.dropFirst().allSatisfy { $0.outcome == nil })
        #expect(content.rows.map(\.isLeader) == [true, false, false, false, false])
        #expect(content.rows.map(\.isDealer) == [true, false, false, false, false])
        #expect(content.rows.map(\.isMe) == [true, false, false, false, false])
        #expect(content.rows.map(\.ordinal) == ["1st", "2nd", "3rd", "4th", "5th"])
        #expect(content.factLine == "Round 5. Noah knocked on 2.")
        #expect(content.liveKnockLine == nil)
        #expect(content.statusLine == "Round 5. Noah knocked on 2.")
        #expect(content.compactRound == "R6/6")
        #expect(content.updatedAt == 1_792_879_560)
    }

    @Test("Avatars: curated and emoji pass through; guests become a dashed initial")
    func avatars() throws {
        let rows = try content().rows
        #expect(rows[0].avatar == .curated(id: "crow"))
        #expect(rows[1].avatar == .emoji(emoji: "🦊", colorIndex: 0))
        #expect(rows[4].avatar == .initial(letter: "S", isGuest: true))
    }

    @Test("Failed and tied knocks show their math")
    func knockMath() throws {
        // R3: Noah knocked on 8 and Ana had 3 (failed). R2: Ben tied Cleo on 5.
        let afterThree = try content(throughRound: 3)
        #expect(afterThree.rows.first { $0.name == "Noah" }?.delta == "8 + 10")
        #expect(afterThree.rows.first { $0.name == "Noah" }?.outcome == .failed)
        let afterTwo = try content(throughRound: 2)
        #expect(afterTwo.rows.first { $0.name == "Ben" }?.delta == "5")
        #expect(afterTwo.rows.first { $0.name == "Ben" }?.outcome == .tied)
    }

    @Test("The scorekeeper gets Record Round; a guest watching gets nothing")
    func actions() throws {
        #expect(try content().action == LiveActivityButton(kind: .recordRound, title: "Record Round 6"))
        let samContent = try content(viewer: sam)
        #expect(samContent.action == nil)
        #expect(samContent.rows.last?.isMe == true)
        #expect(try content(viewer: .init(seat: nil, isScorekeeper: false)).action == nil)
    }

    @Test("A live knock replaces the fact line (K-23)")
    func liveKnock() throws {
        let content = try content(liveKnock: true)
        #expect(content.liveKnockLine == "Sam knocked · last turns")
        #expect(content.statusLine == "Sam knocked · last turns")
    }

    @Test("Finished: no button, no dealer")
    func finished() throws {
        let content = try content(throughRound: 8, finished: true)
        #expect(content.phase == .finished)
        #expect(content.action == nil)
        #expect(content.rows.map(\.name) == ["Noah", "Ana", "Cleo", "Ben", "Sam"])
        #expect(content.rows.map(\.score) == ["28", "34", "65", "67", "70"])
        #expect(content.rows.allSatisfy { !$0.isDealer })
        #expect(content.metadataLine == "ROUND 8 OF 8")
    }

    @Test("No Live Activity in the lobby")
    func lobby() {
        var game = TestGame(players: 3)
        game.setUp(start: false)
        #expect(LiveActivityContent.contentState(for: game.state, viewer: .init(seat: game.seat(0), isScorekeeper: true), voice: voice) == nil)
    }

    @Test("Self-report: Report Your Hand until this phone has reported (and for seats it reports for)")
    func selfReport() throws {
        var game = TestGame(players: 3)
        game.setUp(mode: .selfReport)
        let me = LiveActivityContent.Viewer(seat: game.seat(1), isScorekeeper: false)
        let before = try #require(LiveActivityContent.contentState(for: game.state, viewer: me, voice: voice))
        #expect(before.action == LiveActivityButton(kind: .reportHand, title: "Report Your Hand"))
        #expect(LiveActivityContent.owesReport(game.state, me: game.seat(1)))

        game.add(.handReported(.init(roundNumber: 1, seatId: game.seat(1), hand: 4, knocked: false)))
        let after = try #require(LiveActivityContent.contentState(for: game.state, viewer: me, voice: voice))
        #expect(after.action == nil)
        #expect(!LiveActivityContent.owesReport(game.state, me: game.seat(1)))
        #expect(LiveActivityContent.owesReport(game.state, me: game.seat(0)))
    }

    @Test("The stale line fills in the update time (N-06)")
    func staleLine() throws {
        let content = try content()
        #expect(content.staleTemplate == "Last update {time} · Open Kedro to catch up")
        #expect(content.staleLine { _ in "9:46" } == "Last update 9:46 · Open Kedro to catch up")
    }

    @Test("Rows read as one VoiceOver element")
    func accessibility() throws {
        let rows = try content().rows
        #expect(rows[1].accessibilityLabel == "Ana, 2nd place, 29 points, last round +9")
        #expect(rows[0].accessibilityLabel == "Noah, 1st place, 26 points, last round landed \u{2212}10, deals")
    }

    @Test("Glance lines fit in 60 characters")
    func glanceLength() throws {
        let content = try content(liveKnock: true)
        for line in [content.metadataLine, content.factLine, content.liveKnockLine, content.staleLine { _ in "11:59 PM" }].compactMap(\.self) {
            #expect(line.count <= 60, "\(line)")
        }
    }

    // MARK: JSON

    @Test("Content state JSON: the shape the broadcast push sends")
    func json() throws {
        let content = try content()
        let data = try JSONEncoder().encode(content)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["phase", "roundNumber", "plannedRounds", "metadataLine", "rows", "factLine", "staleTemplate", "action", "updatedAt"])
        #expect(object["phase"] as? String == "active")
        #expect(object["updatedAt"] as? Int == 1_792_879_560)
        let action = try #require(object["action"] as? [String: Any])
        #expect(action["kind"] as? String == "recordRound")
        let rows = try #require(object["rows"] as? [[String: Any]])
        #expect(rows[0]["outcome"] as? String == "landed")
        #expect(rows[1]["outcome"] == nil)
        #expect(Set(rows[1].keys) == ["id", "name", "rankLabel", "ordinal", "score", "delta", "isMe", "isLeader", "isDealer", "avatar"])
        let avatar = try #require(rows[1]["avatar"] as? [String: Any])
        #expect((avatar["emoji"] as? [String: Any])?["colorIndex"] as? Int == 0)

        let decoded = try JSONDecoder().decode(LiveGameAttributes.ContentState.self, from: data)
        #expect(decoded == content)
    }

    @Test("A full 8-seat table stays well under ActivityKit's 4 KB")
    func payloadSize() throws {
        var content = try content(liveKnock: true)
        let long = String(repeating: "W", count: 20)
        content.rows = (0..<8).map { index in
            LiveStandingRow(
                id: "g:\(UUID().uuidString.lowercased())", name: long, rankLabel: "\(index + 1)=", ordinal: "\(index + 1)th",
                score: "\u{2212}999", delta: "999 + 10", outcome: .failed, isMe: index == 7, isLeader: index == 0, isDealer: index == 3,
                avatar: .emoji(emoji: "🦊", colorIndex: 11)
            )
        }
        let attributes = LiveGameAttributes(gameID: UUID().uuidString.lowercased(), tableWord: "Cold Deck", mySeatID: "g:\(UUID().uuidString.lowercased())")
        let size = try JSONEncoder().encode(content).count + JSONEncoder().encode(attributes).count
        #expect(size < 3_000, "\(size) bytes")
    }

    @Test("Updates skip content that only changed its timestamp")
    func differs() throws {
        let content = try content()
        var later = content
        later.updatedAt += 60
        #expect(!LiveActivityController.differs(later, from: content))
        later.factLine = "Round 6. Sam knocked on 1."
        #expect(LiveActivityController.differs(later, from: content))
        #expect(LiveActivityController.differs(content, from: nil))
    }

    @Test("Attributes carry the game, table word and this phone's seat")
    func attributes() {
        let state = PreviewData.sampleState(throughRound: 5)
        let attributes = LiveActivityContent.attributes(for: state, viewer: noah)
        #expect(attributes.gameID == PreviewData.sampleGameID.uuidString.lowercased())
        #expect(attributes.tableWord == "Cold Deck")
        #expect(attributes.mySeatID == PreviewData.noahSeat.rawValue)
    }
}
