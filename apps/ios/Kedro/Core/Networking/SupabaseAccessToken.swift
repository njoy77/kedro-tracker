import Foundation
import Supabase
import Synchronization

/// Bridges the AuthStore's Supabase client to `APIClient.accessToken` and Realtime, so the rest of
/// networking needn't know about Supabase sessions.
///
/// `AppModel` builds its `APIClient` before the `AuthStore` exists, so the default client reads its
/// token through `SupabaseAccessToken.current`, which answers nil until `register(_:)` is called
/// with the AuthStore's client (`NetworkServices.install(in:auth:)` does this at launch).
nonisolated enum SupabaseAccessToken {
    private static let registered = Mutex<SupabaseClient?>(nil)

    /// Makes `current` read tokens from this client (the AuthStore's).
    static func register(_ client: SupabaseClient) {
        registered.withLock { $0 = client }
    }

    /// The registered client, if any.
    static var client: SupabaseClient? {
        registered.withLock { $0 }
    }

    /// The current access token from the registered client (refreshed by Supabase when needed), or
    /// nil when signed out or nothing is registered yet. The DEBUG test user has no Supabase
    /// session, so it gets nil and stays local.
    static let current: @Sendable () async -> String? = {
        guard let client = registered.withLock({ $0 }) else { return nil }
        return try? await client.auth.session.accessToken
    }

    /// A token provider bound to one client.
    static func provider(for client: SupabaseClient) -> @Sendable () async -> String? {
        { try? await client.auth.session.accessToken }
    }
}
