import AuthenticationServices
import Observation
import Supabase

/// Owns the Supabase client and the signed-in state of the app.
@Observable
final class AuthStore {
    enum State: Equatable {
        /// Restoring a saved session at launch.
        case loading
        case signedOut
        case signedIn(User)
    }

    enum SignInError: LocalizedError {
        case missingIdentityToken

        var errorDescription: String? {
            switch self {
            case .missingIdentityToken: "Apple didn't return an identity token. Please try again."
            }
        }
    }

    private(set) var state: State = .loading

    /// Email of the signed-in user. With "Hide My Email" this is an Apple private relay address.
    var email: String? {
        if case .signedIn(let user) = state { user.email } else { nil }
    }
    let client: SupabaseClient

    /// The signed-in user's ID and first name, so the rest of the app needn't import Supabase.
    var signedInUser: SignedInUser? {
        guard case .signedIn(let user) = state else { return nil }
        let name = user.userMetadata["given_name"]?.stringValue ?? user.userMetadata["full_name"]?.stringValue
        return SignedInUser(id: user.id, displayName: name)
    }

    @ObservationIgnored private var pendingNonce: AppleSignInNonce?

    init(client: SupabaseClient = AuthStore.makeClient()) {
        self.client = client
    }

    static func makeClient() -> SupabaseClient {
        SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    /// Mirrors Supabase auth events into `state`. Call once from the root view's `.task`.
    func observeAuthChanges() async {
        for await (_, session) in client.auth.authStateChanges {
            state = session.map { .signedIn($0.user) } ?? .signedOut
        }
    }

    // MARK: Sign in with Apple

    /// Configures the Apple ID request. Pass to `SignInWithAppleButton`'s `onRequest`.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce()
        pendingNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce.hashed
    }

    /// Exchanges the Apple credential for a Supabase session. Returns without error if the user cancels.
    func completeSignIn(with result: Result<ASAuthorization, any Error>) async throws {
        let nonce = pendingNonce
        pendingNonce = nil

        let authorization: ASAuthorization
        do {
            authorization = try result.get()
        } catch let error as ASAuthorizationError where error.code == .canceled {
            return
        }

        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let nonce
        else {
            throw SignInError.missingIdentityToken
        }

        try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce.raw)
        )

        // Apple only shares the user's name on their first sign-in, so save it to their profile now.
        if let fullName = credential.fullName, let name = Self.formatted(fullName) {
            var metadata: [String: AnyJSON] = ["full_name": .string(name)]
            if let given = fullName.givenName { metadata["given_name"] = .string(given) }
            if let family = fullName.familyName { metadata["family_name"] = .string(family) }
            _ = try? await client.auth.update(user: UserAttributes(data: metadata))
        }
    }

    func signOut() async throws {
        #if DEBUG
        if case .signedIn(let user) = state, user.id == Self.testUserID {
            state = .signedOut
            return
        }
        #endif
        try await client.auth.signOut()
    }

    #if DEBUG
    // MARK: Test user

    /// Fixed, and the same as the sample data's Noah, so demo data (`DemoDataSeeder`) shows up
    /// as "You" and the local profile survives relaunches.
    static let testUserID = PreviewData.noah.id.rawValue

    /// Signs in a local stand-in user without Apple or Supabase. Debug builds only, for working in
    /// the Simulator until Sign in with Apple is provisioned. The user has no Supabase session.
    func signInAsTestUser() {
        let now = Date.now
        state = .signedIn(User(
            id: Self.testUserID,
            appMetadata: [:],
            userMetadata: ["full_name": .string("Noah"), "given_name": .string("Noah")],
            aud: "authenticated",
            email: "test@kedro.dev",
            createdAt: now,
            updatedAt: now
        ))
    }
    #endif

    private static func formatted(_ name: PersonNameComponents) -> String? {
        let value = name.formatted()
        return value.isEmpty ? nil : value
    }
}

/// A signed-in account, as the rest of the app sees it.
struct SignedInUser: Equatable {
    let id: UUID
    let displayName: String?
}
