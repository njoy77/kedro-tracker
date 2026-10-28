import SwiftUI

// STUB: owned by talk. Replace this file's contents; keep the type name and initializer.

/// The Talk sheet: canned and custom taunts (design §8.1). Present at .medium.
struct TalkSheet: View {
    let session: GameSession
    let target: TauntTarget

    var body: some View {
        ContentUnavailableView(
            "Talk",
            systemImage: "bubble.left.and.text.bubble.right",
            description: Text("Coming soon.")
        )
        .navigationTitle("Talk")
    }
}

#Preview {
    TalkSheet(session: PreviewData.sampleSession(), target: .table).previewEnvironment()
}
