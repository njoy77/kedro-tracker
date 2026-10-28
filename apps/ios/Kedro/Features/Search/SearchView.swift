import SwiftUI

// STUB: owned by lobby. Replace this file's contents; keep the type name and initializer.

/// The Search tab: find any player by name or @handle. Root of the Search tab's stack; don't add a NavigationStack.
struct SearchView: View {
    var body: some View {
        ContentUnavailableView(
            "Search",
            systemImage: "magnifyingglass",
            description: Text("Coming soon.")
        )
        .navigationTitle("Search")
    }
}

#Preview {
    NavigationStack { SearchView() }.previewEnvironment()
}
