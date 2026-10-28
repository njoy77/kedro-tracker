import SwiftUI

// STUB: owned by stats. Replace this file's contents; keep the type name and initializer.

/// Kedro Wrapped for a year (design §12.9).
struct WrappedView: View {
    let year: Int

    var body: some View {
        ContentUnavailableView(
            "Wrapped",
            systemImage: "sparkles",
            description: Text("Coming soon.")
        )
        .navigationTitle("Wrapped")
    }
}

#Preview {
    NavigationStack { WrappedView(year: 2026) }.previewEnvironment()
}
