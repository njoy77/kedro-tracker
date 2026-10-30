import Foundation
import Network
import OSLog

/// How `TableLink` reaches other phones: host (advertise + accept), browse, and connect.
/// Implementations: `BonjourLinkNetworking` (primary), `MultipeerLinkNetworking` (fallback),
/// `InMemoryLinkNetworking` (tests and previews).
protocol TableLinkNetworking: AnyObject {
    var source: DiscoveredTable.Source { get }

    /// Starts advertising a table and accepting connections. The stream yields each new
    /// connection and finishes when hosting stops or fails.
    func startHosting(_ advertisement: TableAdvertisement) throws -> AsyncStream<any LinkChannel>

    /// Replaces the advertised TXT record (round state, seats, hub).
    func updateAdvertisement(_ advertisement: TableAdvertisement)

    func stopHosting()

    /// Tables currently visible. Yields the full set whenever it changes.
    func browse() -> AsyncStream<[DiscoveredTable]>

    /// Opens a connection to a discovered table's hub (ready to send).
    func connect(to table: DiscoveredTable) async throws -> any LinkChannel
}

/// The primary transport: Bonjour `_kedro-table._tcp` with peer-to-peer (AWDL), TLS-PSK.
///
/// Browsing uses the iOS 26 `NetworkBrowser`; hosting and connections use `NWListener` /
/// `NWConnection` because only they accept a TLS pre-shared key (see `TableLinkParameters`).
final class BonjourLinkNetworking: TableLinkNetworking {
    let source = DiscoveredTable.Source.bonjour
    private var listener: NWListener?
    private var endpoints: [String: NWEndpoint] = [:]
    private let queue = DispatchQueue(label: "com.njoy77.kedro.link.listener")
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "TableLink")

    func startHosting(_ advertisement: TableAdvertisement) throws -> AsyncStream<any LinkChannel> {
        stopHosting()
        let listener = try NWListener(using: TableLinkParameters.make(for: advertisement.game))
        listener.service = Self.service(for: advertisement)
        let (stream, continuation) = AsyncStream.makeStream(of: (any LinkChannel).self)
        let log = log
        listener.newConnectionHandler = { connection in
            let channel = NetworkLinkChannel(connection: connection)
            channel.start()
            continuation.yield(channel)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                log.error("Listener failed: \(error.localizedDescription, privacy: .public)")
                continuation.finish()
            case .cancelled:
                continuation.finish()
            default:
                break
            }
        }
        continuation.onTermination = { _ in listener.cancel() }
        listener.start(queue: queue)
        self.listener = listener
        return stream
    }

    func updateAdvertisement(_ advertisement: TableAdvertisement) {
        listener?.service = Self.service(for: advertisement)
    }

    func stopHosting() {
        listener?.cancel()
        listener = nil
    }

    func browse() -> AsyncStream<[DiscoveredTable]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [DiscoveredTable].self, bufferingPolicy: .bufferingNewest(1))
        let log = log
        let task = Task { [weak self] in
            let browser = NetworkBrowser(
                for: .bonjour(TableAdvertisement.serviceType, includeTxtRecord: true),
                using: TableLinkParameters.browsing()
            )
            do {
                try await browser.run { endpoints in
                    var tables: [DiscoveredTable] = []
                    for endpoint in endpoints {
                        guard let advertisement = TableAdvertisement(txtRecord: endpoint.txtRecord) else { continue }
                        self?.endpoints[endpoint.id] = endpoint.nwEndpoint
                        tables.append(DiscoveredTable(id: endpoint.id, advertisement: advertisement, source: .bonjour))
                    }
                    continuation.yield(tables)
                }
            } catch is CancellationError {
            } catch {
                log.error("Browser stopped: \(error.localizedDescription, privacy: .public)")
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func connect(to table: DiscoveredTable) async throws -> any LinkChannel {
        guard let endpoint = endpoints[table.id] else { throw LinkChannelError.closed }
        let channel = NetworkLinkChannel(connection: NWConnection(to: endpoint, using: TableLinkParameters.make(for: table.advertisement.game)))
        channel.start()
        try await channel.waitUntilReady(timeout: .seconds(5))
        return channel
    }

    private static func service(for advertisement: TableAdvertisement) -> NWListener.Service {
        NWListener.Service(name: advertisement.serviceName, type: TableAdvertisement.serviceType, txtRecord: advertisement.txtRecord)
    }
}

// MARK: - In memory

/// A shared in-memory "room" where `InMemoryLinkNetworking` phones see and reach each other.
/// Used by tests and previews; no radios involved.
final class InMemoryTableAir {
    fileprivate struct Host {
        var advertisement: TableAdvertisement
        var inbound: AsyncStream<any LinkChannel>.Continuation
    }

    fileprivate var hosts: [String: Host] = [:] {
        didSet { publish() }
    }
    private var browsers: [UUID: AsyncStream<[DiscoveredTable]>.Continuation] = [:]

    init() {}

    fileprivate var tables: [DiscoveredTable] {
        hosts.sorted { $0.key < $1.key }.map { DiscoveredTable(id: $0.key, advertisement: $0.value.advertisement, source: .bonjour) }
    }

    fileprivate func browse() -> AsyncStream<[DiscoveredTable]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [DiscoveredTable].self, bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        browsers[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.browsers[token] = nil }
        }
        continuation.yield(tables)
        return stream
    }

    private func publish() {
        let current = tables
        for browser in browsers.values { browser.yield(current) }
    }
}

final class InMemoryLinkNetworking: TableLinkNetworking {
    let source = DiscoveredTable.Source.bonjour
    private let air: InMemoryTableAir
    private let hostID = UUID().uuidString

    init(air: InMemoryTableAir) {
        self.air = air
    }

    func startHosting(_ advertisement: TableAdvertisement) throws -> AsyncStream<any LinkChannel> {
        let (stream, continuation) = AsyncStream.makeStream(of: (any LinkChannel).self)
        air.hosts[hostID] = .init(advertisement: advertisement, inbound: continuation)
        return stream
    }

    func updateAdvertisement(_ advertisement: TableAdvertisement) {
        air.hosts[hostID]?.advertisement = advertisement
    }

    func stopHosting() {
        air.hosts[hostID]?.inbound.finish()
        air.hosts[hostID] = nil
    }

    func browse() -> AsyncStream<[DiscoveredTable]> {
        air.browse()
    }

    func connect(to table: DiscoveredTable) async throws -> any LinkChannel {
        guard let host = air.hosts[table.id] else { throw LinkChannelError.closed }
        let (local, remote) = InMemoryLinkChannel.pair()
        host.inbound.yield(remote)
        return local
    }
}
