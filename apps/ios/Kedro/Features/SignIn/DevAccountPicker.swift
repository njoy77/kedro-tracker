#if DEBUG
import Foundation
import SwiftUI
import Synchronization

/// DEBUG only: the test account this phone is signed in as on the local test server
/// (apps/api `bun run dev:seed`, which loads the web app's players and games). Kept in
/// UserDefaults so it survives relaunches; its token is `dev:<id>` (`SupabaseAccessToken.devToken`).
enum DevAccountSession {
    private static let key = "debug.devAccount"

    static var saved: (id: UUID, name: String)? {
        guard let value = UserDefaults.standard.string(forKey: key) else { return nil }
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[0]) else { return nil }
        SupabaseAccessToken.devToken.withLock { $0 = token(for: id) }
        return (id, parts[1])
    }

    static func save(id: UUID, name: String) {
        UserDefaults.standard.set("\(id.uuidString)|\(name)", forKey: key)
        SupabaseAccessToken.devToken.withLock { $0 = token(for: id) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        SupabaseAccessToken.devToken.withLock { $0 = nil }
    }

    static func token(for id: UUID) -> String { "dev:\(id.uuidString.lowercased())" }
}

/// One account from `GET /dev/accounts`.
struct DevAccount: Decodable, Identifiable, Hashable {
    var id: UUID
    var displayName: String
    var handle: String
    var gamesClaimed: Int
}

/// DEBUG only: signs in as one of the local test server's accounts, standing in for Sign in with
/// Apple until the developer account is approved. Adopts the server's profile, skips onboarding,
/// and the account's history syncs down like any sign-in.
struct DevAccountPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var accounts: [DevAccount] = []
    @State private var failure: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List(accounts) { account in
                Button {
                    Task { await signIn(account) }
                } label: {
                    LabeledContent {
                        Text(account.gamesClaimed == 1 ? "1 game" : "\(account.gamesClaimed) games")
                    } label: {
                        Text(account.displayName)
                        Text("@\(account.handle)")
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                } else if let failure {
                    ContentUnavailableView("No Test Server", systemImage: "server.rack", description: Text(failure))
                }
            }
            .navigationTitle("Test Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        defer { isLoading = false }
        let url = AppConfig.apiBaseURL.appending(path: "dev/accounts")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            accounts = try JSONDecoder().decode([String: [DevAccount]].self, from: data)["accounts"] ?? []
            if accounts.isEmpty { failure = "The server has no test accounts. Start it with bun run dev:seed." }
        } catch {
            failure = "Start it with bun run --filter '@kedro/api' dev:seed, then try again."
        }
    }

    private func signIn(_ account: DevAccount) async {
        DevAccountSession.save(id: account.id, name: account.displayName)
        do {
            try await Self.adoptProfile(app: app)
            app.preferences.hasCompletedOnboarding = true
            auth.signInAsDevAccount(id: account.id, name: account.displayName)
            dismiss()
        } catch {
            DevAccountSession.clear()
            failure = error.localizedDescription
        }
    }

    /// Makes the phone's profile the server's, so signing in doesn't send the old one over it.
    static func adoptProfile(app: AppModel) async throws {
        let player = try await app.api.me()
        app.profiles.save(LocalProfile(
            identity: .player(player.id), displayName: player.displayName,
            handle: player.handle, avatar: player.avatar, titleID: player.titleID
        ))
    }
}

#Preview {
    DevAccountPicker()
        .previewEnvironment()
}
#endif
