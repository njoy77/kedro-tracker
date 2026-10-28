import SwiftUI

// STUB: owned by table. Replace this file's contents; keep the type name and initializer.

/// History: Scores grid, On the record, Feed (design §9.1). Also embedded by GameRecordView for finished games.
struct HistorySheet: View {
    let session: GameSession

    var body: some View {
        ContentUnavailableView(
            "History",
            systemImage: "clock.arrow.circlepath",
            description: Text("Coming soon.")
        )
        .navigationTitle("History")
    }
}

#Preview {
    HistorySheet(session: PreviewData.sampleSession(throughRound: 8, finished: true)).previewEnvironment()
}
