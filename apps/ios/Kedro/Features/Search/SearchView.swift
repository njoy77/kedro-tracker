import SwiftUI

/// The Search tab: find any player by name or @handle (PRD §3.1) and open their profile.
/// Root of the Search tab's stack; doesn't create a NavigationStack.
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @State private var playedTogether: [PlayerID: Int] = [:]

    var body: some View {
        PlayerSearchList(caption: { PlayerRow.playedCaption(playedTogether[$0.id]) }) { player in
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
    NavigationStack { SearchView() }.previewEnvironment()
}
