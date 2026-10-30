import CryptoKit
import Foundation
import Network
import Synchronization

/// Connection parameters for the table link: TLS 1.2 with a pre-shared key derived from the
/// table token (`TableKey`), TCP keepalive, and peer-to-peer (AWDL) so phones find each other
/// without Wi-Fi.
///
/// SDK note: the iOS 26 structured `TLS` protocol builder used by `NetworkListener` and
/// `NetworkConnection` has no pre-shared-key option, so the data connections use `NWListener`
/// and `NWConnection` with `sec_protocol_options_add_pre_shared_key`. Browsing uses the iOS 26
/// `NetworkBrowser` (see `BonjourLinkNetworking`).
nonisolated enum TableLinkParameters {
    static func make(for game: GameID) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let key = TableKey.preSharedKey(for: game).withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = TableKey.pskIdentity.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, key as __DispatchData, identity as __DispatchData)
        if let suite = tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256)) {
            sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions, suite)
        }
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        tcp.noDelay = true
        tcp.connectionTimeout = 5

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }

    /// Browsing needs no TLS, only peer-to-peer.
    static func browsing() -> NWParameters {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// A `LinkChannel` over an `NWConnection`. Callbacks run on a private serial queue; the frame
/// decoder is only touched there.
nonisolated final class NetworkLinkChannel: LinkChannel {
    let id = UUID()
    let messages: AsyncThrowingStream<LinkMessage, any Error>
    private let continuation: AsyncThrowingStream<LinkMessage, any Error>.Continuation
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let decoder = Mutex(FrameDecoder())
    private let readiness = Mutex<Readiness>(.waiting([]))

    private enum Readiness {
        case waiting([CheckedContinuation<Void, any Error>])
        case ready
        case failed(any Error)
    }

    init(connection: NWConnection) {
        self.connection = connection
        queue = DispatchQueue(label: "com.njoy77.kedro.link.\(UUID().uuidString.prefix(8))")
        (messages, continuation) = AsyncThrowingStream.makeStream(of: LinkMessage.self)
    }

    /// Starts the connection and the receive loop.
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                resolveReadiness(nil)
            case .failed(let error):
                resolveReadiness(error)
                continuation.finish(throwing: error)
            case .cancelled:
                resolveReadiness(LinkChannelError.closed)
                continuation.finish()
            case .waiting(let error):
                // No route yet (Local Network off, peer gone). TableLink's timeouts decide.
                _ = error
            default:
                break
            }
        }
        continuation.onTermination = { [weak self] _ in self?.connection.cancel() }
        connection.start(queue: queue)
        receiveNext()
    }

    /// Waits until the TLS handshake finishes, or throws after `timeout`.
    func waitUntilReady(timeout: Duration) async throws {
        // On timeout, fail the waiters and cancel the connection (which also ends `messages`).
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self else { return }
            resolveReadiness(LinkChannelError.timedOut)
            connection.cancel()
        }
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { (pending: CheckedContinuation<Void, any Error>) in
            let immediate: Result<Void, any Error>? = readiness.withLock { readiness in
                switch readiness {
                case .ready: return .success(())
                case .failed(let error): return .failure(error)
                case .waiting(var list):
                    list.append(pending)
                    readiness = .waiting(list)
                    return nil
                }
            }
            if let immediate { pending.resume(with: immediate) }
        }
    }

    private func resolveReadiness(_ error: (any Error)?) {
        let waiters: [CheckedContinuation<Void, any Error>] = readiness.withLock { readiness in
            guard case .waiting(let list) = readiness else { return [] }
            readiness = error.map { .failed($0) } ?? .ready
            return list
        }
        for waiter in waiters {
            if let error { waiter.resume(throwing: error) } else { waiter.resume() }
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    let decoded = try decoder.withLock { try $0.messages(from: data) }
                    for message in decoded { continuation.yield(message) }
                } catch {
                    continuation.finish(throwing: error)
                    connection.cancel()
                    return
                }
            }
            if let error {
                continuation.finish(throwing: error)
            } else if isComplete {
                continuation.finish()
                connection.cancel()
            } else {
                receiveNext()
            }
        }
    }

    func send(_ message: LinkMessage) async throws {
        let frame = try LinkFrame.encode(message)
        try await withCheckedThrowingContinuation { (sent: CheckedContinuation<Void, any Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error { sent.resume(throwing: error) } else { sent.resume() }
            })
        }
    }

    func close() {
        connection.cancel()
        continuation.finish()
    }
}
