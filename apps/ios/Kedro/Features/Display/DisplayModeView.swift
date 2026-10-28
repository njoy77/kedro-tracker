import SwiftUI

// STUB: owned by table. Replace this file's contents; keep the type name and initializer.

/// Table display mode: the landscape shared scoreboard (design §6.3).
struct DisplayModeView: View {
    let session: GameSession

    var body: some View {
        ContentUnavailableView(
            "Display Mode",
            systemImage: "rectangle.on.rectangle",
            description: Text("Coming soon.")
        )
        .navigationTitle("Display Mode")
    }
}

#Preview {
    DisplayModeView(session: PreviewData.sampleSession()).previewEnvironment()
}
