import SwiftUI

/// Splash while the saved session is restored, then onboarding (first launch, or signed out
/// without a guest profile), then the tabs.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(AuthStore.self) private var auth
    @State private var minimumSplashElapsed = false

    private var showsSplash: Bool {
        !minimumSplashElapsed || auth.state == .loading
    }

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { true } else { false }
    }

    var body: some View {
        ZStack {
            if showsSplash {
                SplashView()
                    .transition(.opacity)
            } else if app.needsOnboarding(isSignedIn: isSignedIn) {
                OnboardingFlow()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: showsSplash)
        .animation(.smooth, value: app.needsOnboarding(isSignedIn: isSignedIn))
        .toastHost(app.toasts)
        .task { await auth.observeAuthChanges() }
        .task { await app.start() }
        #if DEBUG
        .task { await DebugLaunch.run(app: app, auth: auth) }
        #endif
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            minimumSplashElapsed = true
        }
        .onChange(of: auth.signedInUser, initial: true) { _, user in
            if let user {
                app.didSignIn(userID: user.id, displayName: user.displayName)
            }
        }
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
