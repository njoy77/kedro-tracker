import SwiftUI

/// A stored game's record, pushed from history lists (`AppRoute.gameHistory`). Loads a
/// read-only session and shows the Table agent's `HistorySheet` content.
struct GameRecordView: View {
    let gameID: GameID

    @Environment(AppModel.self) private var app
    @State private var session: GameSession?
    @State private var failed = false

    var body: some View {
        Group {
            if let session {
                HistorySheet(session: session)
            } else if failed {
                ContentUnavailableView("Game Not Found", systemImage: "suit.spade", description: Text("This game isn't on this phone."))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(session?.state.config.tableWord ?? "Game")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: gameID) {
            do {
                let loaded = try await app.makeSession(for: gameID)
                if loaded.operations.isEmpty { failed = true } else { session = loaded }
            } catch {
                failed = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        GameRecordView(gameID: PreviewData.sampleGameID)
    }
    .previewEnvironment()
}
