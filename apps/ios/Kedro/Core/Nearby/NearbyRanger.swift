import Foundation
import NearbyInteraction
import Observation
import OSLog

/// Distance to nearby tables with Nearby Interaction (UWB, design §5.2): under ~3 m reads
/// "At your table". One `NISession` per peer; tokens travel over a peek connection on the table
/// link (`LinkMessage.nearbyToken`). Phones without UWB return no tokens, and tables are then
/// ordered by played-with overlap instead.
@Observable
final class NearbyRanger: NearbyTokenExchange {
    /// Meters, by peer key.
    private(set) var distances: [String: Double] = [:]

    @ObservationIgnored private var sessions: [String: NISession] = [:]
    @ObservationIgnored private var delegates: [String: RangerDelegate] = [:]
    @ObservationIgnored private var configurations: [String: NINearbyPeerConfiguration] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "Nearby")

    static var isSupported: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    func distance(to peer: String) -> Double? { distances[peer] }

    func localToken(for peer: String) -> Data? {
        guard Self.isSupported, let token = session(for: peer).discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    func didReceive(_ token: Data, from peer: String) {
        guard Self.isSupported,
              let remote = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: token) else { return }
        let configuration = NINearbyPeerConfiguration(peerToken: remote)
        configurations[peer] = configuration
        session(for: peer).run(configuration)
    }

    func endSession(for peer: String) {
        sessions.removeValue(forKey: peer)?.invalidate()
        delegates[peer] = nil
        configurations[peer] = nil
        distances[peer] = nil
    }

    private func session(for peer: String) -> NISession {
        if let existing = sessions[peer] { return existing }
        let session = NISession()
        let delegate = RangerDelegate(peer: peer, ranger: self)
        session.delegate = delegate
        session.delegateQueue = .main
        sessions[peer] = session
        delegates[peer] = delegate
        return session
    }

    fileprivate func update(_ peer: String, distance: Double?) {
        distances[peer] = distance
    }

    fileprivate func resume(_ peer: String) {
        guard let configuration = configurations[peer] else { return }
        sessions[peer]?.run(configuration)
    }

    fileprivate func invalidated(_ peer: String, error: String) {
        log.info("Nearby session ended: \(error, privacy: .public)")
        sessions[peer] = nil
        delegates[peer] = nil
        distances[peer] = nil
    }
}

/// `NISessionDelegate` for one peer. Callbacks arrive on the main queue (`delegateQueue`) but the
/// protocol is nonisolated, so they hop explicitly.
private final class RangerDelegate: NSObject, NISessionDelegate {
    let peer: String
    weak var ranger: NearbyRanger?

    init(peer: String, ranger: NearbyRanger) {
        self.peer = peer
        self.ranger = ranger
    }

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        let distance = nearbyObjects.first?.distance.map(Double.init)
        let peer = peer
        Task { @MainActor in self.ranger?.update(peer, distance: distance) }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        let peer = peer
        Task { @MainActor in self.ranger?.update(peer, distance: nil) }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        let peer = peer
        Task { @MainActor in self.ranger?.resume(peer) }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: any Error) {
        let peer = peer
        let message = error.localizedDescription
        Task { @MainActor in self.ranger?.invalidated(peer, error: message) }
    }
}
