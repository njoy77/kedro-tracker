import Foundation
import Testing
@testable import Kedro

@Suite("HLC merge and convergence")
@MainActor
struct ConvergenceTests {
    @Test("After receiving a remote timestamp, local ticks sort after it")
    func clockMerge() {
        // Device A's clock runs 10 s behind device B's.
        let a = HybridLogicalClock(node: "a") { 1_000_000 }
        let b = HybridLogicalClock(node: "b") { 1_010_000 }
        let fromB = b.tick()
        a.receive(fromB)
        let next = a.tick()
        #expect(next > fromB)
        #expect(next.wallMs == fromB.wallMs)

        // Equal wall clocks: the counter breaks the tie, and stays monotonic.
        let c = HybridLogicalClock(node: "c") { 1_010_000 }
        c.receive(fromB)
        let first = c.tick()
        let second = c.tick()
        #expect(first > fromB && second > first)
    }

    @Test("The HLC string sorts like the HLC")
    func stringOrder() throws {
        let stamps = [
            HLC(wallMs: 9, counter: 0, node: "z"),
            HLC(wallMs: 10, counter: 0, node: "a"),
            HLC(wallMs: 10, counter: 2, node: "a"),
            HLC(wallMs: 10, counter: 10, node: "a"),
            HLC(wallMs: 1_761_700_000_000, counter: 0, node: "a"),
        ]
        #expect(stamps.map(\.stringValue).sorted() == stamps.map(\.stringValue))
        for stamp in stamps {
            #expect(HLC(string: stamp.stringValue) == stamp)
        }
    }

    @Test("Two phones that merge each other's logs in any order fold to the same game")
    func mergeOrderIndependent() {
        var game = TestGame(players: 3)
        game.setUp()
        game.record([4, 10, 12], knocker: 0, device: game.deviceA)
        // Concurrent: A records round 2 while B edits round 1 (later HLC wins for the edit).
        game.record([6, 2, 9], knocker: 1, device: game.deviceA)
        game.add(.roundEdited(.init(round: game.round(1, [4, 11, 12], knocker: 0))), device: game.deviceB)
        let all = game.operations

        let phoneA = GameState.fold(all.shuffled(), gameID: game.gameID)
        let phoneB = GameState.fold(all.reversed() + all.prefix(3), gameID: game.gameID) // with duplicates
        #expect(phoneA.rounds.map(\.round) == phoneB.rounds.map(\.round))
        #expect(phoneA.standings.map(\.total) == phoneB.standings.map(\.total))
        #expect(phoneA.rounds.first?.round.hands[game.seat(1)] == 11)
    }

    @Test("Two phones on the table link converge on the union of their logs")
    func linkConvergence() async throws {
        var game = TestGame(players: 3)
        game.setUp()
        game.record([4, 10, 12], knocker: 0, device: game.deviceA)
        let shared = game.operations
        // Each phone also made one operation the other never saw (both offline).
        game.record([6, 2, 9], knocker: 1, device: game.deviceA)
        let onlyA = Array(game.operations.suffix(1))
        game.add(.reactionAdded(.init(roundNumber: 1, seatId: game.seat(1), reaction: .fire)), device: game.deviceB)
        let onlyB = Array(game.operations.suffix(1))

        let air = InMemoryTableAir()
        let storeA = InMemoryGameStore(operations: shared + onlyA)
        let storeB = InMemoryGameStore(operations: shared + onlyB)
        let host = LocalIdentity(deviceID: game.deviceA, player: game.seats[0].player, displayName: "P0")
        let guest = LocalIdentity(deviceID: game.deviceB, player: game.seats[1].player, displayName: "P1")
        // Seated people are admitted by identity, which needs a verified (server-attested) hello.
        let server = TestLinkServer()
        let linkA = TableLink(
            store: storeA, identity: { host }, secrets: InMemoryTableSecretStore(),
            networking: InMemoryLinkNetworking(air: air), isFallbackEnabled: { false },
            linkIdentity: try server.identityService(for: host), timing: .fast
        )
        let linkB = TableLink(
            store: storeB, identity: { guest }, secrets: InMemoryTableSecretStore(),
            networking: InMemoryLinkNetworking(air: air), isFallbackEnabled: { false },
            linkIdentity: try server.identityService(for: guest), timing: .fast
        )
        defer {
            linkA.leave()
            linkB.leave()
        }

        linkA.join(game.gameID)
        #expect(await eventually { linkA.role == .hub })
        linkB.join(game.gameID)
        #expect(await eventually { linkB.role == .spoke(hub: game.deviceA) })

        let expected = Set(game.operations.map(\.opId))
        var opsA: Set<UUID> = []
        var opsB: Set<UUID> = []
        for _ in 0..<200 where opsA != expected || opsB != expected {
            opsA = Set(try await storeA.operations(for: game.gameID).map(\.opId))
            opsB = Set(try await storeB.operations(for: game.gameID).map(\.opId))
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(opsA == expected)
        #expect(opsB == expected)
        #expect(linkA.connectedPeerCount == 1)
        #expect(linkB.connectedPeerCount == 1)

        // Live: an operation sent by the spoke reaches the hub's store.
        game.record([1, 2, 3], knocker: 2, device: game.deviceB)
        let live = Array(game.operations.suffix(1))
        try await storeB.append(live)
        linkB.broadcast(live)
        let liveID = try #require(live.first?.opId)
        var arrived = false
        for _ in 0..<200 where !arrived {
            arrived = try await storeA.operations(for: game.gameID).contains { $0.opId == liveID }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(arrived)
        let stateA = try #require(try await storeA.gameState(game.gameID))
        let stateB = try #require(try await storeB.gameState(game.gameID))
        #expect(stateA.standings.map(\.total) == stateB.standings.map(\.total))
    }

    @Test("When the hub leaves, the lowest remaining seat takes over")
    func hubFailover() async throws {
        var game = TestGame(players: 3)
        game.setUp()
        let deviceC = DeviceID()
        let air = InMemoryTableAir()
        let server = TestLinkServer()
        func makeLink(_ device: DeviceID, seat: Int) throws -> TableLink {
            let me = LocalIdentity(deviceID: device, player: game.seats[seat].player, displayName: "P\(seat)")
            return TableLink(
                store: InMemoryGameStore(operations: game.operations), identity: { me }, secrets: InMemoryTableSecretStore(),
                networking: InMemoryLinkNetworking(air: air), isFallbackEnabled: { false },
                linkIdentity: try server.identityService(for: me), timing: .fast
            )
        }
        let hub = try makeLink(game.deviceA, seat: 0)
        let seat1 = try makeLink(game.deviceB, seat: 1)
        let seat2 = try makeLink(deviceC, seat: 2)
        defer {
            hub.leave()
            seat1.leave()
            seat2.leave()
        }
        hub.join(game.gameID)
        #expect(await eventually { hub.role == .hub })
        seat2.join(game.gameID)
        seat1.join(game.gameID)
        #expect(await eventually { seat1.role.isConnected && seat2.role.isConnected && hub.members.count == 3 })

        hub.leave()
        #expect(await eventually(timeout: .seconds(4)) { seat1.role == .hub })
        #expect(await eventually(timeout: .seconds(4)) { seat2.role == .spoke(hub: game.deviceB) })
    }
}

extension TableLinkTiming {
    /// Short timeouts for tests.
    static let fast = TableLinkTiming(
        hostSearch: .milliseconds(50), guestSearch: .milliseconds(300), failoverBase: .milliseconds(50),
        failoverStep: .milliseconds(300), retryDelay: .milliseconds(50), fallbackDelay: .seconds(5),
        pingInterval: .milliseconds(200), peerTimeout: .seconds(2)
    )
}
