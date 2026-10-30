import Foundation
import Testing
@testable import Kedro

/// Records calls and fails on demand (offline, signed out).
nonisolated final class FakeTrashTalkAPI: TrashTalkAPI, @unchecked Sendable {
    enum Call: Equatable {
        case check(String)
        case report(ReportTargetType, String, ReportReason)
        case block(PlayerID)
        case unblock(PlayerID)
        case receipt(GameID, PlayerID, String)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _fails = false
    var checkResponse = TauntCheckResponse(allowed: true)

    var calls: [Call] { lock.withLock { _calls } }
    var fails: Bool {
        get { lock.withLock { _fails } }
        set { lock.withLock { _fails = newValue } }
    }

    private func record(_ call: Call) throws {
        try lock.withLock {
            if _fails { throw TrashTalkAPIError.notSignedIn }
            _calls.append(call)
        }
    }

    func checkTaunt(_ text: String) async throws -> TauntCheckResponse {
        try record(.check(text))
        return checkResponse
    }

    func report(_ targetType: ReportTargetType, targetID: String, reason: ReportReason) async throws {
        try record(.report(targetType, targetID, reason))
    }

    func block(_ player: PlayerID) async throws { try record(.block(player)) }
    func unblock(_ player: PlayerID) async throws { try record(.unblock(player)) }

    func sendReceipt(gameID: GameID, to player: PlayerID, receiptKey: String) async throws {
        try record(.receipt(gameID, player, receiptKey))
    }
}

/// A fresh, isolated UserDefaults suite.
func scratchDefaults() -> UserDefaults {
    let name = "kedro.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Moderation: mute, block, report")
struct ModerationStoreTests {
    private let game = GameID()
    private let otherGame = GameID()
    private let ana = PlayerRef.player(PlayerID())
    private let sam = PlayerRef.guest(GuestID())

    private func taunt(from person: PlayerRef?, custom: Bool = false) -> TauntRecord {
        TauntRecord(
            tauntId: UUID(), opId: UUID(), roundNumber: 1, from: person?.seatID, fromName: "Ana", target: .table,
            content: custom ? .custom(text: "say less") : .canned(id: "TT-10"), at: .now, isRetracted: false
        )
    }

    @Test("Mute this game hides their taunts in this game only")
    func muteThisGame() {
        let store = ModerationStore(defaults: scratchDefaults())
        store.mute(ana.seatID, scope: .thisGame, in: game)
        #expect(store.hides(taunt(from: ana), in: game, showsCustom: true))
        #expect(!store.hides(taunt(from: ana), in: otherGame, showsCustom: true))
        #expect(store.muteScope(of: ana.seatID, in: game) == .thisGame)
        #expect(store.muteScope(of: ana.seatID, in: otherGame) == nil)
        #expect(!store.hides(taunt(from: sam), in: game, showsCustom: true))
    }

    @Test("Mute always follows them to every game; unmute restores")
    func muteAlways() {
        let store = ModerationStore(defaults: scratchDefaults())
        store.mute(ana.seatID, scope: .always, in: game)
        #expect(store.hides(taunt(from: ana), in: otherGame, showsCustom: true))
        store.unmute(ana.seatID, in: game)
        #expect(!store.hides(taunt(from: ana), in: game, showsCustom: true))
        #expect(!store.hides(taunt(from: ana), in: otherGame, showsCustom: true))
    }

    @Test("Mutes are silent: nothing goes to the server")
    func muteIsLocal() {
        let store = ModerationStore(defaults: scratchDefaults())
        store.mute(ana.seatID, scope: .always, in: game)
        #expect(store.pending.isEmpty)
    }

    @Test("Block hides their taunts and receipts everywhere and queues the server call")
    func block() async {
        let store = ModerationStore(defaults: scratchDefaults())
        store.block(ana)
        #expect(store.isBlocked(ana))
        #expect(store.isBlocked(ana.seatID))
        #expect(store.hides(taunt(from: ana), in: otherGame, showsCustom: true))
        #expect(store.hidesReceipt(from: ana.seatID, in: otherGame))
        #expect(store.pending == [.block(ana.playerID ?? PlayerID())])

        let api = FakeTrashTalkAPI()
        await store.flush(using: api)
        #expect(store.pending.isEmpty)
        #expect(api.calls == [.block(ana.playerID ?? PlayerID())])
    }

    @Test("Unblocking before the block reached the server cancels it")
    func unblockBeforeSync() {
        let store = ModerationStore(defaults: scratchDefaults())
        store.block(ana)
        store.unblock(ana)
        #expect(!store.isBlocked(ana))
        #expect(store.pending.isEmpty)
    }

    @Test("Guests are blocked on this phone only")
    func blockGuest() {
        let store = ModerationStore(defaults: scratchDefaults())
        store.block(sam)
        #expect(store.isBlocked(sam))
        #expect(store.pending.isEmpty)
    }

    @Test("Report hides the taunt at once and stays queued while offline")
    func report() async {
        let store = ModerationStore(defaults: scratchDefaults())
        let reported = taunt(from: ana, custom: true)
        store.report(reported, reason: .slur)
        #expect(store.hides(reported, in: game, showsCustom: true))
        #expect(!store.hides(taunt(from: ana, custom: true), in: game, showsCustom: true))

        let api = FakeTrashTalkAPI()
        api.fails = true
        await store.flush(using: api)
        #expect(store.pending.count == 1)
        api.fails = false
        await store.flush(using: api)
        #expect(store.pending.isEmpty)
        #expect(api.calls == [.report(.taunt, reported.tauntId.uuidString.lowercased(), .slur)])
    }

    @Test("Custom taunts are hidden when custom taunts are off (Settings or under 18)")
    func customOff() {
        let store = ModerationStore(defaults: scratchDefaults())
        #expect(store.hides(taunt(from: ana, custom: true), in: game, showsCustom: false))
        #expect(!store.hides(taunt(from: ana, custom: false), in: game, showsCustom: false))
    }

    @Test("Retracted taunts are hidden")
    func retracted() {
        let store = ModerationStore(defaults: scratchDefaults())
        var retracted = taunt(from: ana)
        retracted.isRetracted = true
        #expect(store.hides(retracted, in: game, showsCustom: true))
    }

    @Test("Everything survives a relaunch")
    func persistence() {
        let defaults = scratchDefaults()
        let reported = taunt(from: sam, custom: true)
        do {
            let store = ModerationStore(defaults: defaults)
            store.mute(sam.seatID, scope: .thisGame, in: game)
            store.block(ana)
            store.report(reported, reason: .abuse)
        }
        let relaunched = ModerationStore(defaults: defaults)
        #expect(relaunched.muteScope(of: sam.seatID, in: game) == .thisGame)
        #expect(relaunched.isBlocked(ana))
        #expect(relaunched.reportedTaunts.contains(reported.tauntId))
        #expect(relaunched.pending.count == 2)
    }
}

@Suite("Taunt moderator: on-device filter, then the server")
struct TauntModeratorTests {
    private let filter = TauntFilter(blocklist: TauntBlocklist(
        version: 1, blockedSHA256: [TauntBlocklist.hash("zorblax")], profanityStems: [], profanityWords: []
    ))

    @Test("The on-device filter blocks before the server is asked")
    func localBlock() async {
        let api = FakeTrashTalkAPI()
        let verdict = await TauntModerator(filter: filter, api: api).review("z0rblax")
        #expect(verdict == .blocked(reason: "filter"))
        #expect(api.calls.isEmpty)
    }

    @Test("The server can block what the phone let through")
    func serverBlock() async {
        let api = FakeTrashTalkAPI()
        api.checkResponse = TauntCheckResponse(allowed: false, reason: "identity")
        let verdict = await TauntModerator(filter: filter, api: api).review("  something   new ")
        #expect(verdict == .blocked(reason: "identity"))
        #expect(api.calls == [.check("something new")])
    }

    @Test("Offline, the on-device verdict stands")
    func offline() async {
        let api = FakeTrashTalkAPI()
        api.fails = true
        let verdict = await TauntModerator(filter: filter, api: api).review("if sam lands this i'm moving")
        #expect(verdict == .allowed(text: "if sam lands this i'm moving", serverChecked: false))
    }

    @Test("Empty and over-80 taunts don't go out")
    func lengths() async {
        let moderator = TauntModerator(filter: filter, api: FakeTrashTalkAPI())
        #expect(await moderator.review("   \n ") == .empty)
        #expect(await moderator.review(String(repeating: "a", count: 81)) == .tooLong)
        let exactly80 = String(repeating: "a", count: 80)
        #expect(await moderator.review(exactly80) == .allowed(text: exactly80, serverChecked: true))
    }
}
