import SwiftUI

// STUB: owned by stats. Replace this file's contents; keep the type name and initializer.

/// Head-to-head between two people (design §12.3).
struct HeadToHeadView: View {
    let a: PlayerRef
    let b: PlayerRef

    var body: some View {
        ContentUnavailableView(
            "Head to Head",
            systemImage: "person.2",
            description: Text("Coming soon.")
        )
        .navigationTitle("Head to Head")
    }
}

#Preview {
    NavigationStack { HeadToHeadView(a: PreviewData.noah.ref, b: PreviewData.ana.ref) }.previewEnvironment()
}
