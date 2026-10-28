import SwiftUI

// STUB: owned by stats. Replace this file's contents; keep the type name and initializer.

/// The Hall of Shame (design §12.8).
struct HallOfShameView: View {
    var body: some View {
        ContentUnavailableView(
            "Hall of Shame",
            systemImage: "flame",
            description: Text("Coming soon.")
        )
        .navigationTitle("Hall of Shame")
    }
}

#Preview {
    NavigationStack { HallOfShameView() }.previewEnvironment()
}
