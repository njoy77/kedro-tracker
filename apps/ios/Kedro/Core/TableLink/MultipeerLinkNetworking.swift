import Foundation
import MultipeerConnectivity
import OSLog
import Synchronization

/// The fallback transport (design §5.2): MultipeerConnectivity, behind `NetworkFlags.multipeerFallback`,
/// for when no Network-framework peer-to-peer path comes up. Same frames, same star; the session
/// is encrypted (`.required`). Discovery info is a trimmed TXT record (MC allows ~400 bytes).
final class MultipeerLinkNetworking: NSObject, TableLinkNetworking {
    /// Distinct from the Bonjour service (`_kedro-table._tcp`): MultipeerConnectivity advertises
    /// `_kedro-mc._tcp`/`._udp`, and sharing a name would make the Bonjour browser see MC peers.
    static let serviceType = "kedro-mc"

    let source = DiscoveredTable.Source.multipeer
    private let peer: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var inbound: AsyncStream<any LinkChannel>.Continuation?
    private var channels: [MCPeerID: MultipeerLinkChannel] = [:]
    private var visible: [String: (peer: MCPeerID, table: DiscoveredTable)] = [:] {
        didSet { publishVisible() }
    }
    private var browser: MCNearbyServiceBrowser?
    private var browsers: [UUID: AsyncStream<[DiscoveredTable]>.Continuation] = [:]
    private var pendingConnects: [MCPeerID: CheckedContinuation<Void, any Error>] = [:]
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "TableLink.Multipeer")

    init(device: DeviceID) {
        peer = MCPeerID(displayName: "kedro-\(device.uuidString.prefix(8))")
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    // MARK: Hosting

    func startHosting(_ advertisement: TableAdvertisement) throws -> AsyncStream<any LinkChannel> {
        stopHosting()
        let (stream, continuation) = AsyncStream.makeStream(of: (any LinkChannel).self)
        inbound = continuation
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: Self.discoveryInfo(advertisement), serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        return stream
    }

    func updateAdvertisement(_ advertisement: TableAdvertisement) {
        guard let current = advertiser else { return }
        current.stopAdvertisingPeer()
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: Self.discoveryInfo(advertisement), serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        inbound?.finish()
        inbound = nil
    }

    private static func discoveryInfo(_ advertisement: TableAdvertisement) -> [String: String] {
        let keep: Set<String> = ["v", "t", "w", "h", "n", "g", "r", "st", "f", "hub", "ho"]
        return advertisement.txtDictionary.filter { keep.contains($0.key) }
    }

    // MARK: Browsing

    func browse() -> AsyncStream<[DiscoveredTable]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [DiscoveredTable].self, bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        browsers[token] = continuation
        if browser == nil {
            let browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
        }
        continuation.yield(visible.values.map(\.table))
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.endBrowse(token) }
        }
        return stream
    }

    private func endBrowse(_ token: UUID) {
        browsers[token] = nil
        if browsers.isEmpty {
            browser?.stopBrowsingForPeers()
            browser = nil
            visible = [:]
        }
    }

    private func publishVisible() {
        let tables = visible.values.map(\.table)
        for continuation in browsers.values { continuation.yield(tables) }
    }

    func connect(to table: DiscoveredTable) async throws -> any LinkChannel {
        guard let target = visible[table.id]?.peer, let browser else { throw LinkChannelError.closed }
        if let existing = channels[target] { return existing }
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.pendingConnects.removeValue(forKey: target)?.resume(throwing: LinkChannelError.timedOut)
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { (connected: CheckedContinuation<Void, any Error>) in
            pendingConnects[target] = connected
            browser.invitePeer(target, to: session, withContext: nil, timeout: 5)
        }
        return channel(for: target)
    }

    private func channel(for peer: MCPeerID) -> MultipeerLinkChannel {
        if let existing = channels[peer] { return existing }
        let box = SendablePeer(peer)
        let channel = MultipeerLinkChannel(session: SendableSession(session), peer: box) { [weak self] in
            Task { @MainActor in self?.channels[box.value] = nil }
        }
        channels[peer] = channel
        return channel
    }

    // MARK: Delegate events (hopped to the main actor)

    fileprivate func peerChanged(_ peer: MCPeerID, state: MCSessionState) {
        switch state {
        case .connected:
            if let pending = pendingConnects.removeValue(forKey: peer) {
                _ = channel(for: peer)
                pending.resume()
            } else if let inbound {
                inbound.yield(channel(for: peer))
            }
        case .notConnected:
            pendingConnects.removeValue(forKey: peer)?.resume(throwing: LinkChannelError.closed)
            channels.removeValue(forKey: peer)?.close()
        default:
            break
        }
    }

    fileprivate func received(_ data: Data, from peer: MCPeerID) {
        channels[peer]?.receive(data)
    }

    fileprivate func found(_ peer: MCPeerID, info: [String: String]?) {
        guard let info, let advertisement = TableAdvertisement(txt: info) else { return }
        let id = "mc:" + peer.displayName + ":" + advertisement.game.uuidString
        visible[id] = (peer, DiscoveredTable(id: id, advertisement: advertisement, source: .multipeer))
    }

    fileprivate func lost(_ peer: MCPeerID) {
        visible = visible.filter { $0.value.peer != peer }
    }
}

// MARK: - Delegates

extension MultipeerLinkNetworking: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peer = SendablePeer(peerID)
        Task { @MainActor in self.peerChanged(peer.value, state: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let peer = SendablePeer(peerID)
        Task { @MainActor in self.received(data, from: peer.value) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?) {}

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Admission happens in TableLink (hello/welcome), so every invitation is accepted here.
        let handler = SendableInvitationHandler(invitationHandler)
        Task { @MainActor in handler.value(true, self.session) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let peer = SendablePeer(peerID)
        Task { @MainActor in self.found(peer.value, info: info) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let peer = SendablePeer(peerID)
        Task { @MainActor in self.lost(peer.value) }
    }
}

// MCPeerID and MCSession are immutable identifiers / internally synchronized objects that
// MultipeerConnectivity itself hands across its own queues; they predate Sendable annotations.
nonisolated struct SendablePeer: @unchecked Sendable {
    let value: MCPeerID
    init(_ value: MCPeerID) { self.value = value }
}

nonisolated struct SendableSession: @unchecked Sendable {
    let value: MCSession
    init(_ value: MCSession) { self.value = value }
}

nonisolated struct SendableInvitationHandler: @unchecked Sendable {
    let value: (Bool, MCSession?) -> Void
    init(_ value: @escaping (Bool, MCSession?) -> Void) { self.value = value }
}

/// A `LinkChannel` to one Multipeer peer. Each MC message is one complete frame.
nonisolated final class MultipeerLinkChannel: LinkChannel {
    let id = UUID()
    let messages: AsyncThrowingStream<LinkMessage, any Error>
    private let continuation: AsyncThrowingStream<LinkMessage, any Error>.Continuation
    private let session: SendableSession
    private let peer: SendablePeer
    private let decoder = Mutex(FrameDecoder())
    private let onClose: @Sendable () -> Void

    init(session: SendableSession, peer: SendablePeer, onClose: @escaping @Sendable () -> Void) {
        self.session = session
        self.peer = peer
        self.onClose = onClose
        (messages, continuation) = AsyncThrowingStream.makeStream(of: LinkMessage.self)
    }

    func receive(_ data: Data) {
        do {
            for message in try decoder.withLock({ try $0.messages(from: data) }) {
                continuation.yield(message)
            }
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func send(_ message: LinkMessage) async throws {
        try session.value.send(LinkFrame.encode(message), toPeers: [peer.value], with: .reliable)
    }

    func close() {
        continuation.finish()
        onClose()
    }
}
