import SwiftUI

// STUB: owned by lobby. Replace this file's contents; keep the type name and initializer.

/// Learn Cambio in 2 minutes and the Score a Round drill (design §13.1).
struct LearnView: View {
    var body: some View {
        ContentUnavailableView(
            "Learn Cambio",
            systemImage: "graduationcap",
            description: Text("Coming soon.")
        )
        .navigationTitle("Learn Cambio")
    }
}

#Preview {
    NavigationStack { LearnView() }.previewEnvironment()
}
