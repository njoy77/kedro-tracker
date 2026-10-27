import SwiftUI

struct GamesView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Games Yet",
                systemImage: "suit.spade",
                description: Text("Start a game to track scores.")
            )
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Account", systemImage: "person.crop.circle") {
                        if let email = auth.email {
                            Text(email)
                        }
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task { try? await auth.signOut() }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    GamesView()
        .environment(AuthStore())
}
