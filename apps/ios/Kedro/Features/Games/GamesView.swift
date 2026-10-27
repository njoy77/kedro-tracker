import SwiftUI

struct GamesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Games Yet",
                systemImage: "suit.spade",
                description: Text("Start a game to track scores.")
            )
            .navigationTitle("Games")
        }
    }
}

#Preview {
    GamesView()
}
