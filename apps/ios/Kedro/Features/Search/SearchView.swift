import SwiftUI

/// The Search tab: find any player by name or @handle (PRD §3.1) and open their profile.
/// Root of the Search tab's stack; doesn't create a NavigationStack. `MainTabView` owns the search
/// field (`.searchable` on this tab's stack, shown in the tab bar), so the query comes in.
struct SearchView: View {
    let query: String

    @Environment(AppModel.self) private var app
    @State private var playedTogether: [PlayerID: Int] = [:]

    var body: some View {
        PlayerSearchList(query: query, caption: { PlayerRow.playedCaption(playedTogether[$0.id]) }) { player in
            app.navigate(to: .profile(player.ref), in: .search)
        }
        .navigationTitle("Search")
        .task {
            let playedWith = (try? await app.directory.playedWith()) ?? []
            playedTogether = Dictionary(playedWith.map { ($0.player.id, $0.gamesTogether) }, uniquingKeysWith: max)
        }
    }
}

#Preview {
    @Previewable @State var query = ""
    TabView {
        Tab(role: .search) {
            NavigationStack { SearchView(query: query) }
                .searchable(text: $query, prompt: "Name or @handle")
        }
    }
    .tabViewSearchActivation(.searchTabSelection)
    .previewEnvironment()
}
