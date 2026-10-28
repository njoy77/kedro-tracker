import SwiftUI

// STUB: owned by stats. Replace this file's contents; keep the type name and initializer.

/// The Board tab: sortable leaderboard, records, Not Yet Ranked (design §12.4). Root of the Board tab's stack; don't add a NavigationStack.
struct LeaderboardView: View {
    var body: some View {
        ContentUnavailableView(
            "Board",
            systemImage: "list.number",
            description: Text("Coming soon.")
        )
        .navigationTitle("Board")
    }
}

#Preview {
    NavigationStack { LeaderboardView() }.previewEnvironment()
}
