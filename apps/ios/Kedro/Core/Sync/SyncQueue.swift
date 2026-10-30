import Foundation
import OSLog

/// The offline upload queue: operations waiting for `POST /v1/ops`, kept in fold order and
/// de-duplicated by `opId`. Survives relaunches through a `SyncQueueStorage`.
///
/// The queue only ever holds operations the server hasn't confirmed. Upload is idempotent by
/// `opId`, so sending one twice (a crash between upload and save) is harmless.
nonisolated struct SyncQueue: Sendable, Equatable {
    private(set) var operations: [GameOperation] = []

    init(_ operations: [GameOperation] = []) {
        self.operations = []
        enqueue(operations)
    }

    var count: Int { operations.count }
    var isEmpty: Bool { operations.isEmpty }

    /// Adds operations not already queued. Returns how many were new.
    @discardableResult
    mutating func enqueue(_ new: [GameOperation]) -> Int {
        var known = Set(operations.map(\.opId))
        let added = new.filter { known.insert($0.opId).inserted }
        guard !added.isEmpty else { return 0 }
        operations = (operations + added).sorted(by: GameOperation.foldOrder)
        return added.count
    }

    /// The next upload batch: the oldest operations first, so a game's `GameCreated` reaches the
    /// server before anything that depends on it.
    func nextBatch(limit: Int) -> [GameOperation] {
        Array(operations.prefix(limit))
    }

    /// Drops operations the server has answered for (stored or refused).
    mutating func remove(_ opIDs: Set<UUID>) {
        operations.removeAll { opIDs.contains($0.opId) }
    }

    func contains(_ opID: UUID) -> Bool {
        operations.contains { $0.opId == opID }
    }
}

/// Where the queue and pull cursors are kept between launches.
protocol SyncQueueStorage: AnyObject, Sendable {
    func loadQueue() -> [GameOperation]
    func saveQueue(_ operations: [GameOperation])
    /// The newest server HLC seen per game (the `?after=` cursor).
    func loadCursors() -> [GameID: HLC]
    func saveCursors(_ cursors: [GameID: HLC])
}

/// The queue as JSON in Application Support (excluded from backups), cursors alongside.
final class FileSyncQueueStorage: SyncQueueStorage {
    private let directory: URL
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Sync")

    init(directory: URL? = nil) {
        let base = directory ?? URL.applicationSupportDirectory.appending(path: "Sync", directoryHint: .isDirectory)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = base
        try? url.setResourceValues(values)
    }

    private var queueURL: URL { directory.appending(path: "queue.json") }
    private var cursorsURL: URL { directory.appending(path: "cursors.json") }

    func loadQueue() -> [GameOperation] {
        read([GameOperation].self, from: queueURL) ?? []
    }

    func saveQueue(_ operations: [GameOperation]) {
        write(operations, to: queueURL)
    }

    func loadCursors() -> [GameID: HLC] {
        guard let raw = read([String: String].self, from: cursorsURL) else { return [:] }
        var cursors: [GameID: HLC] = [:]
        for (game, hlc) in raw {
            if let id = GameID(uuidString: game), let value = HLC(string: hlc) { cursors[id] = value }
        }
        return cursors
    }

    func saveCursors(_ cursors: [GameID: HLC]) {
        let raw = Dictionary(uniqueKeysWithValues: cursors.map { ($0.key.uuidString, $0.value.stringValue) })
        write(raw, to: cursorsURL)
    }

    private func read<Value: Decodable>(_ type: Value.Type, from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try KedroJSON.decoder().decode(type, from: data)
        } catch {
            log.error("Couldn't read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) {
        do {
            try KedroJSON.encoder().encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            log.error("Couldn't save \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Queue storage in memory (tests and previews).
final class InMemorySyncQueueStorage: SyncQueueStorage {
    private(set) var queue: [GameOperation]
    private(set) var cursors: [GameID: HLC]
    /// How many times the queue was saved (tests).
    private(set) var saveCount = 0

    init(queue: [GameOperation] = [], cursors: [GameID: HLC] = [:]) {
        self.queue = queue
        self.cursors = cursors
    }

    func loadQueue() -> [GameOperation] { queue }

    func saveQueue(_ operations: [GameOperation]) {
        queue = operations
        saveCount += 1
    }

    func loadCursors() -> [GameID: HLC] { cursors }
    func saveCursors(_ cursors: [GameID: HLC]) { self.cursors = cursors }
}
