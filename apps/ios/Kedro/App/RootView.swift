import SwiftUI

/// Shows the splash while the saved session is restored, then sign-in or the main app.
struct RootView: View {
    @Environment(AuthStore.self) private var auth
    @State private var minimumSplashElapsed = false

    private var showsSplash: Bool {
        !minimumSplashElapsed || auth.state == .loading
    }

    var body: some View {
        ZStack {
            if showsSplash {
                SplashView()
                    .transition(.opacity)
            } else {
                switch auth.state {
                case .loading, .signedOut:
                    SignInView()
                        .transition(.opacity)
                case .signedIn:
                    MainTabView()
                        .transition(.opacity)
                }
            }
        }
        .animation(.smooth, value: showsSplash)
        .animation(.smooth, value: auth.state)
        .task { await auth.observeAuthChanges() }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            minimumSplashElapsed = true
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
        .environment(AuthStore())
}
