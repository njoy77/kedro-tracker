import SwiftUI

// STUB: owned by talk. Replace this file's contents; keep the type name and initializer.

/// The game feed: rounds, knocks, taunts, reactions, edits (design §8.4).
struct FeedView: View {
    let session: GameSession

    var body: some View {
        ContentUnavailableView(
            "Feed",
            systemImage: "text.bubble",
            description: Text("Coming soon.")
        )
        .navigationTitle("Feed")
    }
}

#Preview {
    FeedView(session: PreviewData.sampleSession(liveKnock: true)).previewEnvironment()
}
