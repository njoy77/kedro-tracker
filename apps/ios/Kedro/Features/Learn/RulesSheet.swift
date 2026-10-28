import SwiftUI

// STUB: owned by lobby. Replace this file's contents; keep the type name and initializer.

/// The searchable rules reference, also a .medium sheet mid-game (design §13.1).
struct RulesSheet: View {
    var body: some View {
        ContentUnavailableView(
            "Rules",
            systemImage: "book",
            description: Text("Coming soon.")
        )
        .navigationTitle("Rules")
    }
}

#Preview {
    NavigationStack { RulesSheet() }.previewEnvironment()
}
