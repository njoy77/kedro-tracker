import Foundation

enum AppConfig {
    /// Base URL of the Kedro API, read from the `KedroAPIBaseURL` Info.plist key.
    static let apiBaseURL: URL = {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "KedroAPIBaseURL") as? String,
            let url = URL(string: value)
        else {
            fatalError("KedroAPIBaseURL is missing or invalid in Info.plist")
        }
        return url
    }()
}
