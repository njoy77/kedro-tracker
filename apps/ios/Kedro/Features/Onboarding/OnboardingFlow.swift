import AuthenticationServices
import SwiftUI

// STUB: owned by lobby. Replace this file's contents; keep the type name and initializer.
// A minimal working welcome so the onboarding gate can be passed: Play as a Guest, Sign in
// with Apple (via the existing SignInView flow), and the DEBUG test user.

/// First launch (design §5.1): welcome, how filthy, your face and handle. Must end by setting
/// `AppPreferences.hasCompletedOnboarding = true` once the phone has a profile (signed in, or
/// `AppModel.playAsGuest`).
struct OnboardingFlow: View {
    @Environment(AppModel.self) private var app
    @Environment(AuthStore.self) private var auth
    @State private var guestName = ""

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { true } else { false }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            LogoView(width: 300)
            Text(app.voice.line("O-01")).kedroFont(.display).foregroundStyle(.cream)
            Text(app.voice.line("O-02"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.silver)
            Spacer()
            if isSignedIn || app.profile?.isGuest == true {
                Button(Literal.text("button.continue")) {
                    app.preferences.hasCompletedOnboarding = true
                }
                .buttonStyle(.kedroPrimary)
            } else {
                TextField("Your first name", text: $guestName)
                    .textContentType(.givenName)
                    .padding()
                    .background(.surface, in: .rect(cornerRadius: 14))
                Button(Literal.text("button.playAsGuest")) {
                    app.playAsGuest(name: guestName)
                    app.preferences.hasCompletedOnboarding = true
                }
                .buttonStyle(.kedroPrimary)
                SignInWithAppleButton(.signIn) { request in
                    auth.prepare(request)
                } onCompletion: { result in
                    Task { try? await auth.completeSignIn(with: result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(.capsule)
                #if DEBUG
                Button("Continue as Test User") { auth.signInAsTestUser() }
                    .font(.subheadline)
                    .foregroundStyle(.silver)
                #endif
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { SuitWatermark() }
        .background(.nightGradient)
        .environment(\.colorScheme, .dark)
    }
}

#Preview {
    OnboardingFlow()
        .previewEnvironment()
}
