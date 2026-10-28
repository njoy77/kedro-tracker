import SwiftUI

// STUB: owned by stats. Replace this file's contents; keep the type name and initializer.

/// Bragging Rights: the badge grid with Next up (design §12.6).
struct BadgesView: View {
    let player: PlayerRef

    var body: some View {
        ContentUnavailableView(
            "Bragging Rights",
            systemImage: "seal",
            description: Text("Coming soon.")
        )
        .navigationTitle("Bragging Rights")
    }
}

#Preview {
    NavigationStack { BadgesView(player: PreviewData.noah.ref) }.previewEnvironment()
}
