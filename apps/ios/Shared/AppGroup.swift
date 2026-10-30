import Foundation

/// The app group shared by Kedro, KedroWidgets and KedroClip.
///
/// Holds the widget snapshot (`WidgetSnapshotStore`), the App Clip's claim token
/// (`ClaimTokenStore`) and Live Activity button requests (`LiveActivityActionInbox`). The
/// identifier comes from each target's Info.plist (`KedroAppGroup` = `$(KEDRO_APP_GROUP)`, set in
/// `Config/*.xcconfig`), so it is defined in exactly one place per target.
nonisolated enum KedroAppGroup {
    /// The fallback matches `KEDRO_APP_GROUP` in the xcconfigs.
    static let identifier: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "KedroAppGroup") as? String,
           !value.isEmpty, !value.hasPrefix("$(") {
            return value
        }
        return "group.com.njoy77.kedro"
    }()

    /// The shared defaults. Falls back to the process's own defaults when the group container
    /// isn't available (unsigned test hosts), so callers never have to unwrap.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// The shared container directory, or nil when the entitlement is missing.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// JSON coders for everything written to the app group. ISO 8601 dates and sorted keys, like
/// `KedroJSON` in the app (which the widget extension doesn't compile).
nonisolated enum SharedJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
