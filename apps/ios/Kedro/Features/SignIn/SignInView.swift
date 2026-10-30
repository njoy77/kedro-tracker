import AuthenticationServices
import SwiftUI

/// The Sign in with Apple button (PRD §3.1, design §5.1), used by onboarding's welcome and by
/// Settings → Account. Signing in gives the phone an account (backend sync, Search Kedro, saved
/// seats, claims, the server taunt check, report upload); `RootView` then calls
/// `AppModel.didSignIn`, which keeps the guest profile's face and name and claims its history.
struct AppleSignInButton: View {
    @Environment(AuthStore.self) private var auth
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            auth.prepare(request)
        } onCompletion: { result in
            Task { await signIn(with: result) }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 52)
        .clipShape(.capsule)
        .disabled(isSigningIn)
        .overlay {
            if isSigningIn {
                ProgressView()
            }
        }
        .alert(
            "Couldn't Sign In",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func signIn(with result: Result<ASAuthorization, any Error>) async {
        // Cancelling the Apple sheet isn't an error worth showing.
        if case .failure(let error as ASAuthorizationError) = result, error.code == .canceled { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await auth.completeSignIn(with: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A standalone sign-in screen (kept for flows that need a full screen).
struct SignInView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(.logo)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300)
                .accessibilityLabel("Kedro")

            Text("Keep score with your crew.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            AppleSignInButton()

            #if DEBUG
            Button("Continue as Test User") {
                auth.signInAsTestUser()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            #endif
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.08, blue: 0.11), .brandBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

#Preview("Sign in screen") {
    SignInView()
        .environment(AuthStore())
}

#Preview("Button") {
    AppleSignInButton()
        .padding()
        .background(.night)
        .environment(AuthStore())
}
