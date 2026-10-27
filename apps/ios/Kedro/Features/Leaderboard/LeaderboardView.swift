import SwiftUI

struct LeaderboardView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Rankings Yet",
                systemImage: "trophy",
                description: Text("Finish a game to see the leaderboard.")
            )
            .navigationTitle("Leaderboard")
        }
    }
}

#Preview {
    LeaderboardView()
}
