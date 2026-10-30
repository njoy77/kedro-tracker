import Foundation
import Synchronization
import Testing
@testable import Kedro

@Suite("Backend sync")
@MainActor
struct BackendSyncTests {
    private struct Fixture {
        var game: TestGame
        var http: MockHTTP
        var storage: InMemorySyncQueueStorage
        var store: InMemoryGameStore
        var sync: BackendSync
    }

    private func makeFixture(
        token: String? = "test-token",
        queued: [GameOperation] = [],
        respond: @escaping @Sendable (MockHTTP.Recorded) throws -> (Int, Data) = BackendSyncTests.acceptEverything
    ) -> Fixture {
        var game = TestGame(players: 3)
        game.setUp()
        let http = MockHTTP(respond)
        let storage = InMemorySyncQueueStorage(queue: queued)
        let store = InMemoryGameStore(operations: game.operations)
        let sync = BackendSync(
            api: .mock(http, token: token), store: store, storage: storage, feed: SilentOpsFeed(),
            policy: SyncRetryPolicy(batchSize: 2, initialDelay: .seconds(60), maxDelay: .seconds(60))
        )
        return Fixture(game: game, http: http, storage: storage, store: store, sync: sync)
    }

    /// `POST /v1/ops` answers every op as accepted; everything else is `{ops: []}`.
    nonisolated static let acceptEverything: @Sendable (MockHTTP.Recorded) throws -> (Int, Data) = { request in
        if request.method == "POST" {
            return (200, MockHTTP.json(OpsUploadResult(accepted: MockHTTP.uploadedOps(request).map(\.opId), duplicates: [])))
        }
        return (200, MockHTTP.json(OpsPage(ops: [])))
    }

    private func uploads(_ http: MockHTTP) -> [MockHTTP.Recorded] {
        http.requests.filter { $0.method == "POST" && $0.path == "/v1/ops" }
    }

    // MARK: Queue

    @Test("Queueing the same operation twice keeps one copy")
    func queueDeduplicates() {
        var game = TestGame(players: 3)
        game.setUp()
        var queue = SyncQueue()
        #expect(queue.enqueue(game.operations) == game.operations.count)
        #expect(queue.enqueue(game.operations) == 0)
        #expect(queue.enqueue(Array(game.operations.prefix(2))) == 0)
        #expect(queue.count == game.operations.count)
        #expect(queue.operations == game.operations.sorted(by: GameOperation.foldOrder))
    }

    @Test("Uploads go out in fold-order batches with the bearer token, and empty the queue")
    func uploadBatches() async {
        let fixture = makeFixture()
        let operations = fixture.game.operations // 5 ops → batches of 2, 2, 1
        fixture.sync.enqueue(operations.reversed())
        await fixture.sync.flush()

        let posts = uploads(fixture.http)
        #expect(posts.count == 3)
        #expect(posts.allSatisfy { $0.authorization == "Bearer test-token" })
        #expect(posts.flatMap(MockHTTP.uploadedOps) == operations.sorted(by: GameOperation.foldOrder))
        #expect(fixture.sync.pendingCount == 0)
        #expect(fixture.storage.queue.isEmpty)
    }

    @Test("The body is the contract's Operation JSON")
    func uploadBody() async throws {
        let fixture = makeFixture()
        let operation = try #require(fixture.game.operations.first)
        fixture.sync.enqueue([operation])
        await fixture.sync.flush()
        let body = try #require(uploads(fixture.http).first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let ops = try #require(json["ops"] as? [[String: Any]])
        let op = try #require(ops.first)
        #expect(Set(op.keys) == ["opId", "gameId", "deviceId", "hlc", "actorPlayerId", "type", "payload"])
        #expect((op["hlc"] as? [String: Any]).map { Set($0.keys) } == ["wallMs", "counter", "node"])
        #expect(op["type"] as? String == "GameCreated")
    }

    @Test("Duplicates count as stored: re-sending an uploaded op is idempotent")
    func duplicatesAreStored() async {
        let fixture = makeFixture { request in
            let ops = MockHTTP.uploadedOps(request).map(\.opId)
            return (200, MockHTTP.json(OpsUploadResult(accepted: [], duplicates: ops)))
        }
        fixture.sync.enqueue(fixture.game.operations)
        await fixture.sync.flush()
        #expect(fixture.sync.pendingCount == 0)

        // Queueing them again (a relay, or a crash before the queue was saved) uploads once more,
        // and the server's duplicates answer clears them again.
        fixture.sync.enqueue(fixture.game.operations)
        await fixture.sync.flush()
        #expect(fixture.sync.pendingCount == 0)
        #expect(uploads(fixture.http).count == 6)
    }

    @Test("Refused operations leave the queue and are reported once")
    func refused() async throws {
        let fixture = makeFixture { request in
            let ops = MockHTTP.uploadedOps(request).map(\.opId)
            return (200, MockHTTP.json(OpsUploadResult(accepted: Array(ops.dropLast()), duplicates: [])))
        }
        var reported: [GameOperation] = []
        fixture.sync.onRefused = { reported += $0 }
        let operations = Array(fixture.game.operations.prefix(2))
        fixture.sync.enqueue(operations)
        await fixture.sync.flush()
        #expect(fixture.sync.pendingCount == 0)
        #expect(reported.map(\.opId) == [try #require(operations.sorted(by: GameOperation.foldOrder).last).opId])
    }

    @Test("Offline: the queue survives a failed upload, then drains")
    func offlineQueue() async {
        let fixture = makeFixture { _ in throw URLError(.notConnectedToInternet) }
        fixture.sync.enqueue(fixture.game.operations)
        await fixture.sync.flush()
        #expect(fixture.sync.pendingCount == fixture.game.operations.count)
        #expect(fixture.storage.queue.count == fixture.game.operations.count)
        #expect(fixture.sync.lastError?.isRetryable == true)

        fixture.http.setResponder(Self.acceptEverything)
        await fixture.sync.reachabilityChanged()
        #expect(fixture.sync.pendingCount == 0)
        #expect(fixture.sync.lastError == nil)
    }

    @Test("A 5xx keeps the queue; a 4xx for one op doesn't block the rest")
    func serverErrors() async throws {
        let fixture = makeFixture { _ in (503, Data()) }
        fixture.sync.enqueue(fixture.game.operations)
        await fixture.sync.flush()
        #expect(fixture.sync.pendingCount == fixture.game.operations.count)

        let bad = try #require(fixture.game.operations.sorted(by: GameOperation.foldOrder).first?.opId)
        fixture.http.setResponder { request in
            let ops = MockHTTP.uploadedOps(request).map(\.opId)
            if ops.contains(bad) { return (422, Data()) }
            return (200, MockHTTP.json(OpsUploadResult(accepted: ops, duplicates: [])))
        }
        await fixture.sync.reachabilityChanged()
        for _ in 0..<50 where fixture.sync.pendingCount > 0 {
            await fixture.sync.flush()
        }
        #expect(fixture.sync.pendingCount == 0)
    }

    @Test("Signed out: nothing is sent and the queue is kept for later")
    func signedOut() async {
        let fixture = makeFixture(token: nil)
        fixture.sync.enqueue(fixture.game.operations)
        await fixture.sync.flush()
        #expect(fixture.http.requests.isEmpty)
        #expect(fixture.sync.pendingCount == fixture.game.operations.count)
        #expect(!fixture.sync.hasAccount)
        #expect(!fixture.sync.isCatchingUp)
    }

    @Test("The queue is restored after a relaunch")
    func restoresQueue() async {
        var game = TestGame(players: 3)
        game.setUp()
        let http = MockHTTP(Self.acceptEverything)
        let sync = BackendSync(
            api: .mock(http), store: InMemoryGameStore(), storage: InMemorySyncQueueStorage(queue: game.operations),
            feed: SilentOpsFeed()
        )
        #expect(sync.pendingCount == game.operations.count)
        await sync.flush()
        #expect(sync.pendingCount == 0)
    }

    // MARK: Pull

    @Test("Pull: whole log first, then after the newest HLC; new ops are stored and yielded")
    func pull() async throws {
        var remote = TestGame(players: 3)
        remote.setUp()
        let first = remote.operations
        remote.record([1, 2, 3], knocker: 0, device: remote.deviceB)
        let later = Array(remote.operations.suffix(1))
        let pages = PageScript([first, later])
        let http = MockHTTP { request in
            if request.method == "GET" { return (200, MockHTTP.json(OpsPage(ops: pages.next()))) }
            return (200, MockHTTP.json(OpsUploadResult(accepted: MockHTTP.uploadedOps(request).map(\.opId), duplicates: [])))
        }
        let store = InMemoryGameStore()
        let storage = InMemorySyncQueueStorage()
        let sync = BackendSync(api: .mock(http), store: store, storage: storage, feed: SilentOpsFeed())
        let incoming = sync.incoming(for: remote.gameID)

        await sync.pull(remote.gameID, full: true)
        await sync.pull(remote.gameID)

        let gets = http.requests.filter { $0.method == "GET" }
        #expect(gets.first?.path == "/v1/games/\(remote.gameID.uuidString)/ops")
        #expect(gets.first?.query["after"] == nil)
        let newest = try #require(first.map(\.hlc).max())
        #expect(gets.last?.query["after"] == newest.stringValue)
        #expect(Set(try await store.operations(for: remote.gameID).map(\.opId)) == Set(remote.operations.map(\.opId)))
        #expect(storage.cursors[remote.gameID] == later.first?.hlc)

        var iterator = incoming.makeAsyncIterator()
        #expect(await iterator.next()?.count == first.count)
        #expect(await iterator.next()?.map(\.opId) == later.map(\.opId))
    }

    @Test("A full pull queues what the server lacks (relaying for the table)")
    func relaysMissing() async throws {
        let fixture = makeFixture { request in
            if request.method == "GET" { return (200, MockHTTP.json(OpsPage(ops: []))) }
            return (200, MockHTTP.json(OpsUploadResult(accepted: MockHTTP.uploadedOps(request).map(\.opId), duplicates: [])))
        }
        await fixture.sync.pull(fixture.game.gameID, full: true)
        await fixture.sync.flush()
        let uploaded = Set(uploads(fixture.http).flatMap(MockHTTP.uploadedOps).map(\.opId))
        #expect(uploaded == Set(fixture.game.operations.map(\.opId)))
    }

    @Test("A server retraction folds in and hides the taunt")
    func serverRetraction() async throws {
        var game = TestGame(players: 3)
        game.setUp()
        let tauntID = UUID()
        game.add(.tauntSent(.init(
            tauntId: tauntID, roundNumber: 1, from: game.seat(0), fromName: "P0", target: .table, content: .custom(text: "nope")
        )))
        let local = game.operations
        game.add(.tauntRetracted(.init(tauntId: tauntID, reason: "filter")), device: DeviceID(), actor: nil)
        let retraction = Array(game.operations.suffix(1))
        let http = MockHTTP { _ in (200, MockHTTP.json(OpsPage(ops: retraction))) }
        let store = InMemoryGameStore(operations: local)
        let sync = BackendSync(api: .mock(http), store: store, storage: InMemorySyncQueueStorage(), feed: SilentOpsFeed())
        #expect(try await store.gameState(game.gameID)?.visibleTaunts.count == 1)
        await sync.pull(game.gameID)
        #expect(try await store.gameState(game.gameID)?.visibleTaunts.isEmpty == true)
    }

    @Test("A refused custom taunt is retracted from every phone")
    func refusedTauntRetracted() async throws {
        var game = TestGame(players: 3)
        game.setUp()
        let me = LocalIdentity(deviceID: game.deviceA, player: game.seats[0].player, displayName: "P0")
        let tauntID = UUID()
        let taunt = game.add(.tauntSent(.init(
            tauntId: tauntID, roundNumber: 1, from: game.seat(0), fromName: "P0", target: .table, content: .custom(text: "too far")
        )))
        let http = MockHTTP { request in
            let ops = MockHTTP.uploadedOps(request).map(\.opId)
            return (200, MockHTTP.json(OpsUploadResult(accepted: ops.filter { $0 != taunt.opId }, duplicates: [])))
        }
        let store = InMemoryGameStore(operations: game.operations)
        let sync = BackendSync(api: .mock(http), store: store, storage: InMemorySyncQueueStorage(), feed: SilentOpsFeed())
        let link = TableLink(
            store: store, identity: { me }, secrets: InMemoryTableSecretStore(),
            networking: InMemoryLinkNetworking(air: InMemoryTableAir()), isFallbackEnabled: { false }
        )
        let transport = NetworkedTransport(
            store: store, link: link, sync: sync, path: FixedNetworkPath(isOnline: true),
            identity: { me }, clock: HybridLogicalClock(device: me.deviceID)
        )
        await transport.send([taunt])
        await sync.flush()
        #expect(await eventually {
            uploads(http).flatMap(MockHTTP.uploadedOps).contains { $0.type == .tauntRetracted }
        })
        #expect(try await store.gameState(game.gameID)?.visibleTaunts.isEmpty == true)
    }

    // MARK: Sync state

    @Test("Sync pill: online, syncing, offline with peers, offline alone")
    func syncState() async {
        let fixture = makeFixture { _ in throw URLError(.timedOut) }
        let me = LocalIdentity(deviceID: fixture.game.deviceA, player: fixture.game.seats[0].player, displayName: "P0")
        let path = FixedNetworkPath(isOnline: true)
        let link = TableLink(
            store: fixture.store, identity: { me }, secrets: InMemoryTableSecretStore(),
            networking: InMemoryLinkNetworking(air: InMemoryTableAir()), isFallbackEnabled: { false }
        )
        let transport = NetworkedTransport(
            store: fixture.store, link: link, sync: fixture.sync, path: path,
            identity: { me }, clock: HybridLogicalClock(device: me.deviceID)
        )
        #expect(transport.syncState == .online)
        await transport.send(fixture.game.operations)
        await fixture.sync.flush()
        #expect(transport.syncState == .syncing)
        path.isOnline = false
        #expect(transport.syncState == .offlineSolo)
        #expect(transport.syncState.copyID == "F-02")
    }
}

/// Hands out scripted pages in order (then empty pages).
private nonisolated final class PageScript: Sendable {
    private let pages: Mutex<[[GameOperation]]>

    init(_ pages: [[GameOperation]]) {
        self.pages = Mutex(pages)
    }

    func next() -> [GameOperation] {
        pages.withLock { $0.isEmpty ? [] : $0.removeFirst() }
    }
}

