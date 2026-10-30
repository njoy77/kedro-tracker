import Foundation
import Supabase

/// Bridges the AuthStore's Supabase client to `APIClient.accessToken` and Realtime, so the rest of
/// networking needn't know about Supabase sessions.
nonisolated enum SupabaseAccessToken {
    /// The current access token (refreshed by Supabase when needed), or nil when signed out.
    /// The DEBUG test user has no Supabase session, so it gets nil and stays local.
    static func provider(for client: SupabaseClient) -> @Sendable () async -> String? {
        { try? await client.auth.session.accessToken }
    }
}
