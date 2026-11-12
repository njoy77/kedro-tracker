import Foundation
import Network
import OSLog

/// Local Network access (design §5.2), which nearby tables need. iOS has no API that reads the
/// permission, so `request()` probes: it advertises a throwaway Bonjour service and browses for
/// it. Seeing its own service means allowed; the browser waiting with a policy-denied error means
/// denied. The first probe on a phone is what shows the system prompt, so only call it from an
/// explicit tap (onboarding's Find Tables Nearby, Play, Settings) or once the player has said yes.
/// Later probes answer without asking.
///
/// The probe uses the tables' own service type (it must be in `NSBonjourServices`); other phones
/// ignore it because it has no table TXT record.
nonisolated enum LocalNetworkAccess {
    enum Status: Sendable, Equatable {
        case allowed
        case denied
        /// No answer in time (the prompt was left open) or the probe couldn't run.
        case unknown
    }

    /// Asks (the first time) or checks (afterwards). `-KedroLocalNetworkDenied` (DEBUG) answers
    /// `.denied`, since the Simulator never asks.
    static func request(timeout: Duration = .seconds(90)) async -> Status {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-KedroLocalNetworkDenied") { return .denied }
        #endif
        let probe = Probe()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                probe.start(timeout: timeout) { continuation.resume(returning: $0) }
            }
        } onCancel: {
            probe.cancel()
        }
    }

    /// `kDNSServiceErr_PolicyDenied`: what the browser waits with when Local Network is off.
    static let policyDenied: DNSServiceErrorType = -65570

    /// Maps the browser's state to an answer, if it gives one.
    static func status(for state: NWBrowser.State) -> Status? {
        switch state {
        case .waiting(.dns(let code)) where code == policyDenied: .denied
        case .failed: .unknown
        default: nil
        }
    }

    /// One listener and one browser, all state on a private queue; finishes exactly once.
    nonisolated private final class Probe: @unchecked Sendable {
        private let queue = DispatchQueue(label: "com.njoy77.kedro.local-network-probe")
        private let name = "kedro-probe-" + UUID().uuidString.prefix(8)
        private var listener: NWListener?
        private var browser: NWBrowser?
        private var finish: (@Sendable (Status) -> Void)?
        private let log = Logger(subsystem: "com.njoy77.kedro", category: "LocalNetwork")

        func start(timeout: Duration, completion: @escaping @Sendable (Status) -> Void) {
            queue.async { [self] in
                finish = completion
                do {
                    let listener = try NWListener(using: .tcp)
                    listener.service = NWListener.Service(name: name, type: TableAdvertisement.serviceType)
                    listener.newConnectionHandler = { $0.cancel() }
                    listener.stateUpdateHandler = { [weak self] state in
                        if case .failed = state { self?.complete(.unknown) }
                    }
                    self.listener = listener
                    listener.start(queue: queue)
                } catch {
                    log.error("Probe listener failed: \(error.localizedDescription, privacy: .public)")
                    complete(.unknown)
                    return
                }

                let browser = NWBrowser(for: .bonjour(type: TableAdvertisement.serviceType, domain: nil), using: NWParameters())
                browser.stateUpdateHandler = { [weak self] state in
                    if let status = LocalNetworkAccess.status(for: state) { self?.complete(status) }
                }
                let name = name
                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    let sawItself = results.contains { result in
                        if case .service(let found, _, _, _) = result.endpoint { found == name } else { false }
                    }
                    if sawItself { self?.complete(.allowed) }
                }
                self.browser = browser
                browser.start(queue: queue)

                let seconds = Double(timeout.components.seconds)
                queue.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.complete(.unknown) }
            }
        }

        func cancel() {
            queue.async { [weak self] in self?.complete(.unknown) }
        }

        /// On `queue`.
        private func complete(_ status: Status) {
            guard let finish else { return }
            self.finish = nil
            listener?.cancel()
            browser?.cancel()
            listener = nil
            browser = nil
            finish(status)
        }
    }
}
