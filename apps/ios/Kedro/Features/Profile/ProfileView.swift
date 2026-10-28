import SwiftUI

// STUB: owned by stats. Replace this file's contents; keep the type name and initializer.

/// A player's profile, also the You tab (design §12.2).
struct ProfileView: View {
    let player: PlayerRef

    var body: some View {
        ContentUnavailableView(
            "Profile",
            systemImage: "person.crop.circle",
            description: Text("Coming soon.")
        )
        .navigationTitle("Profile")
    }
}

#Preview {
    NavigationStack { ProfileView(player: PreviewData.noah.ref) }.previewEnvironment()
}
