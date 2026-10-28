import SwiftUI

// STUB: owned by lobby. Replace this file's contents; keep the type name and initializer.

/// Settings: language level, custom taunts, sounds, learner hints (mockup frame 24).
struct SettingsView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gearshape",
            description: Text("Coming soon.")
        )
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack { SettingsView() }.previewEnvironment()
}
