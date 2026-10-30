import Foundation
import Network
import Observation

/// Whether this phone has a route to the internet (`NWPathMonitor`). Peer-to-peer links don't
/// count: AWDL is excluded from the path the monitor reports.
protocol NetworkPathMonitoring: AnyObject, Sendable {
    var isOnline: Bool { get }
    /// Yields on every change.
    func changes() -> AsyncStream<Bool>
}

@Observable
final class NetworkPath: NetworkPathMonitoring {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.njoy77.kedro.path"))
    }

    isolated deinit {
        monitor.cancel()
    }

    func changes() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        continuations[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[token] = nil }
        }
        return stream
    }

    private func update(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        for continuation in continuations.values { continuation.yield(online) }
    }
}

/// A fixed path (tests and previews).
@Observable
final class FixedNetworkPath: NetworkPathMonitoring {
    var isOnline: Bool {
        didSet {
            guard isOnline != oldValue else { return }
            for continuation in continuations.values { continuation.yield(isOnline) }
        }
    }

    @ObservationIgnored private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init(isOnline: Bool) {
        self.isOnline = isOnline
    }

    func changes() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        continuations[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[token] = nil }
        }
        return stream
    }
}
