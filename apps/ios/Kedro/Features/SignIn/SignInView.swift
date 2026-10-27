import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var auth
    @State private var isSigningIn = false
    @State private var errorMessage: String?

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

            SignInWithAppleButton(.signIn) { request in
                auth.prepare(request)
            } onCompletion: { result in
                Task { await signIn(with: result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .clipShape(.capsule)
            .disabled(isSigningIn)
            .overlay {
                if isSigningIn {
                    ProgressView()
                }
            }
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
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await auth.completeSignIn(with: result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthStore())
}
