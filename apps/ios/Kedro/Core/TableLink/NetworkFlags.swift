import Foundation

/// Feature flags for networking. "Remote" flags are read from `UserDefaults` so a remote config
/// fetch (or a debug menu) can flip them without a release.
///
/// TODO(networking): populate these from a remote config endpoint once the backend has one.
nonisolated enum NetworkFlags {
    enum Key {
        static let multipeerFallback = "kedro.flags.multipeerFallback"
    }

    /// MultipeerConnectivity fallback when no peer-to-peer path is up within 5 s (design §5.2).
    static var multipeerFallback: Bool {
        UserDefaults.standard.bool(forKey: Key.multipeerFallback)
    }
}
