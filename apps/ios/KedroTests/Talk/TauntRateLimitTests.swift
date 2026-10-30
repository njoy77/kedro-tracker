import Foundation
import Testing
@testable import Kedro

@Suite("Taunt rate limits")
struct TauntRateLimitTests {
    /// A started 3-seat game with taunts from seat 0 (device A) and a watcher (device B).
    private func game() -> TestGame {
        var game = TestGame(players: 3)
        game.setUp()
        return game
    }

    private func taunt(
        _ game: inout TestGame, round: Int = 1, from seat: Int?, custom: Bool = false, device: DeviceID? = nil, id: UUID = UUID()
    ) {
        let content: TauntContent = custom ? .custom(text: "custom \(id.uuidString.prefix(4))") : .canned(id: "TT-10")
        game.add(.tauntSent(.init(
            tauntId: id, roundNumber: round, from: seat.map { game.seat($0) }, fromName: seat.map { "P\($0)" } ?? "Watcher",
            target: .table, content: content
        )), device: device)
    }

    @Test("Three per round; the fourth is refused")
    func threePerRound() {
        var game = game()
        for _ in 0..<3 { taunt(&game, from: 0) }
        let allowance = TauntRateLimit.allowance(operations: game.operations, round: 1, seat: game.seat(0), device: game.deviceA)
        #expect(allowance.used == 3)
        #expect(allowance.remaining == 0)
        #expect(!allowance.canSend)
        #expect(!allowance.canSendCustom)
    }

    @Test("At most one custom per round, inside the three")
    func oneCustom() {
        var game = game()
        taunt(&game, from: 0, custom: true)
        let allowance = TauntRateLimit.allowance(operations: game.operations, round: 1, seat: game.seat(0), device: game.deviceA)
        #expect(allowance.canSend)
        #expect(allowance.remaining == 2)
        #expect(!allowance.canSendCustom)
    }

    @Test("The count resets each round and is per sender")
    func perRoundAndSender() {
        var game = game()
        for _ in 0..<3 { taunt(&game, round: 1, from: 0) }
        taunt(&game, round: 1, from: 1)
        let nextRound = TauntRateLimit.allowance(operations: game.operations, round: 2, seat: game.seat(0), device: game.deviceA)
        #expect(nextRound.used == 0)
        #expect(nextRound.canSendCustom)
        let other = TauntRateLimit.allowance(operations: game.operations, round: 1, seat: game.seat(1), device: game.deviceA)
        #expect(other.used == 1)
    }

    @Test("Watchers are counted by phone")
    func watchers() {
        var game = game()
        taunt(&game, from: nil, device: game.deviceB)
        taunt(&game, from: nil, device: game.deviceB)
        taunt(&game, from: 0, device: game.deviceA)
        let watcher = TauntRateLimit.allowance(operations: game.operations, round: 1, seat: nil, device: game.deviceB)
        #expect(watcher.used == 2)
        let otherPhone = TauntRateLimit.allowance(operations: game.operations, round: 1, seat: nil, device: DeviceID())
        #expect(otherPhone.used == 0)
    }

    @Test("A duplicated taunt counts once")
    func duplicates() {
        var game = game()
        let id = UUID()
        taunt(&game, from: 0, id: id)
        taunt(&game, from: 0, id: id)
        let allowance = TauntRateLimit.allowance(operations: game.operations, round: 1, seat: game.seat(0), device: game.deviceA)
        #expect(allowance.used == 1)
    }

    @Test("Receiving phones drop taunts over the limit (a modified client can't flood)")
    func withinLimits() {
        var game = game()
        taunt(&game, from: 0, custom: true)
        taunt(&game, from: 0, custom: true) // second custom: dropped
        taunt(&game, from: 0)
        taunt(&game, from: 0)
        taunt(&game, from: 0) // fourth that fits: dropped
        taunt(&game, from: 1)
        let kept = TauntRateLimit.withinLimits(game.state.taunts)
        #expect(kept.count == 4)
        #expect(kept.filter { $0.from == game.seat(0) }.count == 3)
        #expect(kept.filter { $0.from == game.seat(0) && $0.content.isCustom }.count == 1)
        #expect(kept.contains { $0.from == game.seat(1) })
    }
}
