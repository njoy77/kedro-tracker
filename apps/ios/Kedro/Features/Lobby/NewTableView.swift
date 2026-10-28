import SwiftUI

// STUB: owned by lobby. Replace this file's contents; keep the type name and initializer.

/// The lobby: seats, add players, rounds, scoring, Deal (design §5.6).
struct NewTableView: View {
    var body: some View {
        ContentUnavailableView(
            "New Table",
            systemImage: "suit.spade",
            description: Text("Coming soon.")
        )
        .navigationTitle("New Table")
    }
}

#Preview {
    NavigationStack { NewTableView() }.previewEnvironment()
}
