import SwiftUI

struct PlayersView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Players Yet",
                systemImage: "person.2",
                description: Text("Players you add will appear here.")
            )
            .navigationTitle("Players")
        }
    }
}

#Preview {
    PlayersView()
}
