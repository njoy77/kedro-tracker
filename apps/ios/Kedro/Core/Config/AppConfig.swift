import Foundation

enum AppConfig {
    /// Base URL of the Kedro API, from the `KedroAPIBaseURL` Info.plist key.
    static let apiBaseURL = url(for: "KedroAPIBaseURL")

    /// Supabase project URL, built from `SUPABASE_HOST` in `Config/Secrets.xcconfig`.
    static let supabaseURL = url(for: "SupabaseURL")

    /// Supabase anon (publishable) key, from `SUPABASE_ANON_KEY` in `Config/Secrets.xcconfig`.
    static let supabaseAnonKey = string(for: "SupabaseAnonKey")

    private static func string(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
            fatalError("\(key) is missing from Info.plist. Run `bun run env:pull` from the repo root.")
        }
        return value
    }

    private static func url(for key: String) -> URL {
        guard let url = URL(string: string(for: key)), url.host() != nil else {
            fatalError("\(key) in Info.plist is not a valid URL.")
        }
        return url
    }
}
