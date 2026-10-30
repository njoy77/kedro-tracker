import SwiftUI

/// Searches every Kedro player by display name or @handle through `PlayerDirectory` (blocked
/// players are already excluded). Shared by the Search tab and the lobby's Search Kedro.
struct PlayerSearchList: View {
    /// The caption after the @handle ("Played 3 together").
    var caption: (PlayerSummary) -> String? = { _ in nil }
    /// Results to hide (already seated, yourself).
    var isExcluded: (PlayerSummary) -> Bool = { _ in false }
    /// `.automatic` in the Search tab (the tab bar's search field); a drawer in sheets.
    var placement: SearchFieldPlacement = .automatic
    let onSelect: (PlayerSummary) -> Void

    @Environment(AppModel.self) private var app
    @State private var query = ""
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
        .searchable(text: $query, placement: placement, prompt: "Name or @handle")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
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

#Preview {
    NavigationStack {
        PlayerSearchList { _ in }
            .navigationTitle("Search")
    }
    .previewEnvironment()
}
