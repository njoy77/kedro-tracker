import Foundation
import Observation
import OSLog

/// Supabase-backed sync of the op log (design §5.2 "the backend is just another peer", §11).
///
/// - **Upload**: every operation this phone holds goes into the offline `SyncQueue` and is sent with
///   `POST /v1/ops` in fold-order batches. Upload is idempotent by `opId`: `accepted` and
///   `duplicates` both leave the queue. An operation in neither list was **refused**; it leaves the
///   queue too (retrying can't change the answer) and is reported to `onRefused`, which retracts a
///   refused custom taunt from every phone (design §11). Network and 5xx failures back off
///   exponentially and keep the queue; nothing is lost while offline or signed out.
/// - **Pull**: when a game connects (and whenever the network or the Realtime subscription comes
///   back) the whole log is fetched once, since a phone that was offline can upload operations
///   with an HLC older than our cursor; afterwards `?after=<cursor>` catches up incrementally.
///   Any operation we hold that the server lacks is queued, so a phone with internet relays for
///   the phones at its table that have none.
/// - **Live**: a Realtime subscription per connected game (`OpsFeed`). Decoded rows are used
///   directly; anything else triggers an incremental pull.
///
/// Pulled operations are appended to the `GameStore` (idempotent) and yielded on `incoming(for:)`.
/// Server retractions (`TauntRetracted` from the server's taunt check) arrive like any operation,
/// and the fold hides the taunt.
@Observable
final class BackendSync {
    /// Operations waiting for the server.
    private(set) var pendingCount = 0
    /// A pull is in flight.
    private(set) var isPulling = false
    /// An upload is in flight.
    private(set) var isUploading = false
    /// Whether the phone has an account the API accepts (false for guests and the DEBUG test user).
    private(set) var hasAccount = false
    /// The last failure, cleared on the next success.
    private(set) var lastError: APIError?

    /// Catching up: there's something to send or a pull is running.
    var isCatchingUp: Bool { hasAccount && (pendingCount > 0 || isPulling) }

    // MARK: Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let store: any GameStore
    @ObservationIgnored private let storage: any SyncQueueStorage
    @ObservationIgnored private let feed: any OpsFeed
    @ObservationIgnored private let policy: SyncRetryPolicy
    /// Called with operations the server refused (already removed from the queue).
    @ObservationIgnored var onRefused: ([GameOperation]) -> Void = { _ in }
    /// The table invite of a game this phone was admitted to: the key its codes are made with
    /// (registered with the server so it can check codes) and the current code (sent with uploads,
    /// so the server seats a phone that sat down over the link). nil when this phone has no secret.
    @ObservationIgnored var tableInvite: (GameID) -> (key: Data, code: String)? = { _ in nil }
    @ObservationIgnored private var registeredInviteKeys: Set<GameID> = []
    /// Guests the account claimed, as the server lists them (`pullAccountHistory`).
    @ObservationIgnored var onClaimedGuests: ([GuestID]) -> Void = { _ in }
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "Sync")

    // MARK: State

    @ObservationIgnored private var queue: SyncQueue
    @ObservationIgnored private var cursors: [GameID: HLC]
    @ObservationIgnored private var connected: [GameID: Task<Void, Never>] = [:]
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var continuations: [GameID: [UUID: AsyncStream<[GameOperation]>.Continuation]] = [:]

    init(
        api: APIClient,
        store: any GameStore,
        storage: any SyncQueueStorage = FileSyncQueueStorage(),
        feed: any OpsFeed = SupabaseOpsFeed(),
        policy: SyncRetryPolicy = .standard
    ) {
        self.api = api
        self.store = store
        self.storage = storage
        self.feed = feed
        self.policy = policy
        queue = SyncQueue(storage.loadQueue())
        cursors = storage.loadCursors()
        pendingCount = queue.count
    }

    // MARK: Public API

    /// Queues operations for the server and starts an upload.
    func enqueue(_ operations: [GameOperation]) {
        guard queue.enqueue(operations) > 0 else { return }
        storage.saveQueue(queue.operations)
        pendingCount = queue.count
        scheduleFlush()
    }

    /// Uploads everything queued, batch by batch, until the queue is empty or a call fails.
    /// Concurrent callers share one upload.
    func flush() async {
        if let flushTask { return await flushTask.value }
        let task = Task { await self.uploadAll() }
        flushTask = task
        await task.value
        flushTask = nil
        // Operations queued while the last batch was finishing.
        if hasAccount, !queue.isEmpty, retryTask == nil, lastError == nil {
            scheduleFlush()
        }
    }

    /// Starts pulling and following a game on the backend.
    func connect(to game: GameID) {
        guard connected[game] == nil else { return }
        connected[game] = Task { [weak self] in await self?.follow(game) }
    }

    func disconnect(from game: GameID) {
        connected.removeValue(forKey: game)?.cancel()
    }

    /// Games currently followed.
    var connectedGames: Set<GameID> { Set(connected.keys) }

    /// Operations the backend delivered for a game (already appended to the store).
    func incoming(for game: GameID) -> AsyncStream<[GameOperation]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [GameOperation].self, bufferingPolicy: .unbounded)
        let token = UUID()
        continuations[game, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[game]?[token] = nil }
        }
        return stream
    }

    /// The network came back or the account changed: retry now and re-pull followed games.
    func reachabilityChanged() async {
        failures = 0
        retryTask?.cancel()
        retryTask = nil
        await refreshAccount()
        await flush()
        for game in connected.keys {
            await pull(game, full: true)
        }
    }

    /// Re-reads whether the API will accept calls (signed in with a Supabase session).
    func refreshAccount() async {
        hasAccount = await api.hasAccount()
    }

    /// Downloads every game the account is seated in that this phone doesn't hold yet (PRD §3.2,
    /// §6.4): games played on other phones, guest history moved here by a claim, migrated web
    /// games, and the whole history on a new or reinstalled phone. Finished games already pulled
    /// are skipped. Returns how many games were pulled.
    @discardableResult
    func pullAccountHistory() async -> Int {
        await refreshAccount()
        guard hasAccount else { return 0 }
        let games: [MyGamesResponse.Game]
        do {
            let response = try await api.myGames()
            games = response.games
            onClaimedGuests(response.claimedGuestIds)
        } catch {
            log.info("History list failed: \(String(describing: error), privacy: .public)")
            return 0
        }
        var pulled = 0
        for game in games where !Task.isCancelled {
            let settled = game.status == "finished" || game.status == "abandoned"
            if settled, cursors[game.gameId] != nil { continue }
            await pull(game.gameId, full: cursors[game.gameId] == nil)
            pulled += 1
        }
        return pulled
    }

    /// Fetches a game's operations (`full` ignores the cursor), stores them and yields the new ones.
    func pull(_ game: GameID, full: Bool = false) async {
        await refreshAccount()
        guard hasAccount else { return }
        isPulling = true
        defer { isPulling = false }
        do {
            // The server pages the log (`APIClient.opsPageSize`, fold order): a full page means
            // there may be more after its last operation.
            var after = full ? nil : cursors[game]
            var remote: [GameOperation] = []
            while true {
                let page = try await api.operations(for: game, after: after)
                remote += page
                guard page.count >= APIClient.opsPageSize, let last = page.last?.hlc, last != after else { break }
                after = last
            }
            lastError = nil
            await ingest(remote, game: game)
            if full {
                await queueWhatServerLacks(game, server: Set(remote.map(\.opId)))
            }
        } catch let error as APIError {
            lastError = error
            log.info("Pull failed: \(String(describing: error), privacy: .public)")
        } catch {
            // Cancelled.
        }
    }

    // MARK: Upload

    private func scheduleFlush() {
        guard flushTask == nil, retryTask == nil else { return }
        Task { await flush() }
    }

    private func uploadAll() async {
        await refreshAccount()
        guard hasAccount else { return }
        isUploading = true
        defer { isUploading = false }
        while !queue.isEmpty, !Task.isCancelled {
            let batch = queue.nextBatch(limit: policy.batchSize)
            do {
                let result = try await api.uploadOperations(batch, invites: invites(for: batch))
                failures = 0
                lastError = nil
                await registerInviteKeys(for: batch)
                if handle(result, for: batch) { return scheduleRetry() }
            } catch let error as APIError {
                lastError = error
                if case .notSignedIn = error { hasAccount = false }
                log.info("Upload failed: \(String(describing: error), privacy: .public)")
                if case .notSignedIn = error { return }
                // 404 on POST /v1/ops is `profileRequired`: the account has no player row yet
                // (`AccountSync` sends it right after sign-in). Keep everything and try again.
                if error.isRetryable || error == .unauthorized(401) || error == .badStatus(404) {
                    return scheduleRetry()
                }
                // A request the server can never accept as a whole (encoding, 4xx): answer for
                // each operation alone so one bad operation can't block the rest.
                guard await uploadIndividually(batch) else { return }
            } catch {
                return // Cancelled.
            }
        }
    }

    /// Applies an upload answer: stored operations leave the queue; refused ones too, reported.
    /// Ops refused only because this phone's clock ran ahead stay queued. Returns true when some
    /// did (retry later, with backoff, rather than straight away).
    @discardableResult
    private func handle(_ result: OpsUploadResult, for batch: [GameOperation]) -> Bool {
        let stored = result.stored
        let later = result.clockAhead
        let refused = batch.filter { !stored.contains($0.opId) && !later.contains($0.opId) }
        queue.remove(Set(batch.map(\.opId)).subtracting(later))
        storage.saveQueue(queue.operations)
        pendingCount = queue.count
        if !refused.isEmpty {
            log.notice("The server refused \(refused.count) operation(s)")
            onRefused(refused)
        }
        return !later.isEmpty
    }

    /// Current invite codes for the games in a batch this phone holds a table secret for.
    private func invites(for batch: [GameOperation]) -> [GameID: String] {
        var result: [GameID: String] = [:]
        for game in Set(batch.map(\.gameId)) {
            if let invite = tableInvite(game) { result[game] = invite.code }
        }
        return result
    }

    /// Registers each table's invite key once the server knows the game (first key wins on the
    /// server; refusals such as "not seated yet" are retried with a later batch).
    private func registerInviteKeys(for batch: [GameOperation]) async {
        for game in Set(batch.map(\.gameId)) where !registeredInviteKeys.contains(game) {
            guard let invite = tableInvite(game) else { continue }
            do {
                try await api.registerInviteKey(invite.key, for: game)
                registeredInviteKeys.insert(game)
            } catch APIError.badStatus(409) {
                registeredInviteKeys.insert(game) // another phone at the table registered first
            } catch {
                log.info("Invite key not registered yet: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Uploads a batch one operation at a time; an operation the server rejects outright is
    /// treated as refused. Returns false when uploading should stop for now.
    private func uploadIndividually(_ batch: [GameOperation]) async -> Bool {
        for operation in batch {
            do {
                let result = try await api.uploadOperations([operation], invites: invites(for: [operation]))
                handle(result, for: [operation])
            } catch let error as APIError where error.isRetryable || error == .badStatus(404) {
                scheduleRetry()
                return false
            } catch let error as APIError {
                switch error {
                case .notSignedIn, .unauthorized: return false
                default: handle(OpsUploadResult(accepted: [], duplicates: []), for: [operation])
                }
            } catch {
                return false
            }
        }
        return true
    }

    private func scheduleRetry() {
        failures += 1
        let delay = policy.delay(afterFailures: failures)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            retryTask = nil
            await flush()
        }
    }

    // MARK: Pull and follow

    private func follow(_ game: GameID) async {
        await pull(game, full: true)
        for await event in feed.events(for: game) {
            guard !Task.isCancelled else { return }
            switch event {
            case .operations(let operations):
                await ingest(operations, game: game)
            case .changed:
                await pull(game)
            case .subscribed:
                await pull(game)
            }
        }
    }

    private func ingest(_ remote: [GameOperation], game: GameID) async {
        let relevant = remote.filter { $0.gameId == game }
        guard !relevant.isEmpty else { return }
        if let newest = relevant.map(\.hlc).max(), newest > (cursors[game] ?? HLC(wallMs: 0, node: "")) {
            cursors[game] = newest
            storage.saveCursors(cursors)
        }
        // The server holds these now: nothing to upload for them.
        let held = Set(relevant.map(\.opId))
        if relevant.contains(where: { queue.contains($0.opId) }) {
            queue.remove(held)
            storage.saveQueue(queue.operations)
            pendingCount = queue.count
        }
        let new: [GameOperation]
        do {
            new = try await store.append(relevant)
        } catch {
            log.error("Couldn't store pulled operations: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !new.isEmpty else { return }
        for continuation in (continuations[game] ?? [:]).values {
            continuation.yield(new)
        }
    }

    /// Live games only: a finished game's operations were queued when they were made or relayed,
    /// and this keeps local-only history (such as DEBUG demo data) off the server.
    private func queueWhatServerLacks(_ game: GameID, server: Set<UUID>) async {
        guard let state = try? await store.gameState(game), state.status.isLive,
              let local = try? await store.operations(for: game) else { return }
        let missing = local.filter { !server.contains($0.opId) }
        if !missing.isEmpty { enqueue(missing) }
    }
}

/// Upload batching and backoff.
nonisolated struct SyncRetryPolicy: Sendable {
    var batchSize = 200
    var initialDelay: Duration = .seconds(2)
    var maxDelay: Duration = .seconds(120)

    static let standard = SyncRetryPolicy()

    /// 2 s, 4 s, 8 s … capped at `maxDelay`.
    func delay(afterFailures failures: Int) -> Duration {
        let factor = 1 << min(max(failures - 1, 0), 16)
        return min(initialDelay * factor, maxDelay)
    }
}
