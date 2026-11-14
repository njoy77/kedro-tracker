import SwiftUI

/// Asks once for a real name when a signed-in player is still called the placeholder ("Player"):
/// someone who finished onboarding before it had a name step, after an Apple sign-in that shared
/// no name. Shown by RootView over the tabs; it closes when the name is saved.
struct NameFixSheet: View {
    @Environment(AppModel.self) private var app
    @State private var name = ""

    var body: some View {
        NavigationStack {
            GuestNameStep(name: $name, footnote: OnboardingFlow.playerNameFootnote) {
                app.rename(to: name)
            }
            .background { Rectangle().fill(.nightGradient).ignoresSafeArea() }
        }
        .interactiveDismissDisabled()
        .environment(\.colorScheme, .dark)
    }
}

#Preview {
    Color.night
        .sheet(isPresented: .constant(true)) { NameFixSheet() }
        .previewEnvironment()
}
