import SwiftUI

/// Results for a player search by display name or @handle through `PlayerDirectory` (blocked
/// players are already excluded). It doesn't own a search field: the Search tab's field lives in
/// the tab bar (`MainTabView` applies `.searchable`), so the query comes in.
struct PlayerSearchList: View {
    let query: String
    /// The caption after the @handle ("Played 3 together").
    var caption: (PlayerSummary) -> String? = { _ in nil }
    /// Results to hide (already seated, yourself).
    var isExcluded: (PlayerSummary) -> Bool = { _ in false }
    let onSelect: (PlayerSummary) -> Void

    @Environment(AppModel.self) private var app
    @State private var results: [PlayerSummary] = []
    @State private var isSearching = false
    @State private var failed = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        List {
            ForEach(results.filter { !isExcluded($0) && $0.ref != app.profile?.identity }) { player in
                Button { onSelect(player) } label: {
                    PlayerRow(player: player, caption: caption(player))
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            if trimmed.isEmpty {
                ContentUnavailableView("Find Anyone", systemImage: "magnifyingglass", description: Text("Search by name or @handle."))
            } else if isSearching && results.isEmpty {
                ProgressView()
            } else if failed {
                ContentUnavailableView("Can't Search Right Now", systemImage: "wifi.slash", description: Text(app.voice.line("E-01")))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            }
        }
        .task(id: trimmed) { await search(trimmed) }
    }

    private func search(_ text: String) async {
        guard !text.isEmpty else {
            results = []
            failed = false
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            try await Task.sleep(for: .milliseconds(250))
            results = try await app.directory.search(text)
            failed = false
        } catch is CancellationError {
            return
        } catch {
            failed = true
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        PlayerSearchList(query: "") { _ in }
            .navigationTitle("Search")
    }
    .previewEnvironment()
}

#Preview("Results") {
    NavigationStack {
        PlayerSearchList(query: "ma") { _ in }
            .navigationTitle("Search")
    }
    .previewEnvironment()
}
