import Foundation
import Synchronization

/// A hybrid logical clock timestamp: physical milliseconds plus a logical counter, tie-broken by
/// the node (device) that issued it. Totally ordered and consistent with causality, so every
/// device folds the same operations in the same order (design §11).
///
/// JSON: `{"wallMs":1761700000000,"counter":0,"node":"<deviceId>"}`.
/// String form (`stringValue`, used by `GET /v1/games/:id/ops?after=`): `"<wallMs 15 digits>-<counter 5 digits>-<node>"`,
/// e.g. `"001761700000000-00000-8f14e45f-…"`. Lexicographic order of the string equals HLC order.
nonisolated struct HLC: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    var wallMs: Int64
    var counter: Int
    var node: String

    init(wallMs: Int64, counter: Int = 0, node: String) {
        self.wallMs = wallMs
        self.counter = counter
        self.node = node
    }

    static func < (lhs: HLC, rhs: HLC) -> Bool {
        (lhs.wallMs, lhs.counter, lhs.node) < (rhs.wallMs, rhs.counter, rhs.node)
    }

    /// The wall-clock time of this timestamp.
    var date: Date { Date(timeIntervalSince1970: TimeInterval(wallMs) / 1000) }

    var stringValue: String {
        let wall = String(wallMs)
        let count = String(counter)
        return String(repeating: "0", count: max(0, 15 - wall.count)) + wall
            + "-" + String(repeating: "0", count: max(0, 5 - count.count)) + count
            + "-" + node
    }

    var description: String { stringValue }

    /// Parses `stringValue`.
    init?(string: String) {
        let parts = string.split(separator: "-", maxSplits: 2).map(String.init)
        guard parts.count == 3, let wall = Int64(parts[0]), let count = Int(parts[1]) else { return nil }
        self.init(wallMs: wall, counter: count, node: parts[2])
    }

    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}

/// Issues HLC timestamps for this device. Thread-safe; share one per app (`AppModel.clock`).
nonisolated final class HybridLogicalClock: Sendable {
    let node: String
    private let now: @Sendable () -> Int64
    private let last: Mutex<HLC>

    /// - Parameters:
    ///   - node: This device's ID string.
    ///   - now: Physical clock in milliseconds (injectable for tests).
    init(node: String, now: @escaping @Sendable () -> Int64 = { HLC.milliseconds(.now) }) {
        self.node = node
        self.now = now
        last = Mutex(HLC(wallMs: 0, counter: 0, node: node))
    }

    convenience init(device: DeviceID) {
        self.init(node: device.uuidString)
    }

    /// A timestamp for a local event (sending an operation).
    func tick() -> HLC {
        let physical = now()
        return last.withLock { last in
            if physical > last.wallMs {
                last = HLC(wallMs: physical, counter: 0, node: node)
            } else {
                last = HLC(wallMs: last.wallMs, counter: last.counter + 1, node: node)
            }
            return last
        }
    }

    /// Merges a remote timestamp so later local events sort after everything this device has seen.
    func receive(_ remote: HLC) {
        let physical = now()
        last.withLock { last in
            let wall = max(last.wallMs, remote.wallMs, physical)
            let counter: Int
            if wall == last.wallMs && wall == remote.wallMs {
                counter = max(last.counter, remote.counter) + 1
            } else if wall == last.wallMs {
                counter = last.counter + 1
            } else if wall == remote.wallMs {
                counter = remote.counter + 1
            } else {
                counter = 0
            }
            last = HLC(wallMs: wall, counter: counter, node: node)
        }
    }
}
