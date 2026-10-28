import SwiftUI

// STUB: owned by table. Replace this file's contents; keep the type name and initializer.

/// Game end: the logo lands, winner, standings, highlights, Run It Back (design §10).
struct GameEndView: View {
    let session: GameSession

    var body: some View {
        ContentUnavailableView(
            "Game Over",
            systemImage: "trophy",
            description: Text("Coming soon.")
        )
        .navigationTitle("Game Over")
    }
}

#Preview {
    GameEndView(session: PreviewData.sampleSession(throughRound: 8, finished: true)).previewEnvironment()
}
