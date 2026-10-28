import SwiftUI

// STUB: owned by table. Replace this file's contents; keep the type name and initializer.

/// Record a round: knocker, number pad, card mode, self-report (design §7).
struct RoundSheet: View {
    let session: GameSession

    var body: some View {
        ContentUnavailableView(
            "Record Round",
            systemImage: "number",
            description: Text("Coming soon.")
        )
        .navigationTitle("Record Round")
    }
}

#Preview {
    RoundSheet(session: PreviewData.sampleSession()).previewEnvironment()
}
