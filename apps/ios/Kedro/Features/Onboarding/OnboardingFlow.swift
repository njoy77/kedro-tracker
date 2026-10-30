import SwiftUI

/// First launch (design §5.1): welcome → (guest name) → how filthy → your face → your handle.
///
/// - Guests: welcome → first name → level. Unclaimed guests don't pick a face or handle (§3.5);
///   `AppModel.playAsGuest` stores a claim token so signing in later claims everything.
/// - Signed in (the DEBUG test user until Sign in with Apple ships): welcome → level → face → handle.
///
/// Ends by setting `AppPreferences.hasCompletedOnboarding = true` once the phone has a profile,
/// which lets `RootView` show the tabs. Forced dark (design §3.3: the welcome is always on night).
struct OnboardingFlow: View {
    enum Step: Hashable {
        case guestName
        case level
        case face
        case handle
    }

    @Environment(AppModel.self) private var app
    @Environment(AuthStore.self) private var auth
    @Environment(AppPreferences.self) private var prefs

    @State private var path: [Step] = []
    @State private var guestName = ""
    @State private var level = LanguageLevel.adultDefault
    @State private var avatar: Avatar?
    @State private var handleText = ""
    @State private var handle: Handle?
    @State private var isSaving = false

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { true } else { false }
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStep(
                onPlayAsGuest: { path.append(.guestName) },
                onSignedIn: startSignedInPath
            )
            .navigationDestination(for: Step.self) { step in
                Group {
                    switch step {
                    case .guestName:
                        GuestNameStep(name: $guestName) { path.append(.level) }
                    case .level:
                        LevelPickerStep(level: $level) {
                            if isSignedIn { path.append(.face) } else { finishAsGuest() }
                        }
                    case .face:
                        FaceStep(avatar: $avatar, name: app.profile?.displayName ?? "You") {
                            path.append(.handle)
                        }
                    case .handle:
                        HandleStep(text: $handleText, accepted: $handle, firstName: app.profile?.displayName ?? "") {
                            finishSignedIn()
                        }
                    }
                }
                .background { background }
            }
            .background { background }
        }
        .tint(.kedroRed)
        .environment(\.colorScheme, .dark)
        .onAppear {
            level = prefs.isUnder18 ? .clean : prefs.languageLevel
            if isSignedIn, path.isEmpty { startSignedInPath() }
        }
    }

    private var background: some View {
        ZStack {
            Rectangle().fill(.nightGradient)
            SuitWatermark()
        }
        .ignoresSafeArea()
    }

    private func startSignedInPath() {
        // Returning player signing back in: the gate in RootView opens on its own.
        guard !prefs.hasCompletedOnboarding else { return }
        avatar = app.profile?.avatar
        path = [.level]
    }

    private func finishAsGuest() {
        prefs.languageLevel = level
        app.playAsGuest(name: guestName)
        prefs.hasCompletedOnboarding = true
    }

    private func finishSignedIn() {
        prefs.languageLevel = level
        if var profile = app.profile {
            // Skipped the face step: keep the random starter emoji `didSignIn` assigned.
            profile.avatar = avatar ?? profile.avatar ?? .randomStarter()
            if let handle { profile.handle = handle }
            app.profiles.save(profile)
        }
        // PUT /v1/players/me. A 409 means the handle was taken in the meantime: stay on the
        // handle step with the field cleared. Offline, the profile is sent on the next edit.
        isSaving = true
        Task {
            defer { isSaving = false }
            if await app.syncProfile() == .handleTaken {
                handle = nil
                app.toasts.show(HandleProblem.taken.message)
                return
            }
            prefs.hasCompletedOnboarding = true
        }
    }
}

// MARK: - Steps

/// The welcome (mockup frame 1): logo, O-01, O-02, Play as a Guest, Sign in with Apple,
/// the Learn link (O-04) and "Got a claim code?".
struct WelcomeStep: View {
    var onPlayAsGuest: () -> Void
    var onSignedIn: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(AuthStore.self) private var auth
    @State private var isLearning = false
    @State private var isClaiming = false
    #if DEBUG
    @State private var isPickingTestAccount = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    LogoView(width: 300)
                        .padding(.top, 48)
                    Text(app.voice.line("O-01"))
                        .kedroFont(.display)
                        .foregroundStyle(.cream)
                        .multilineTextAlignment(.center)
                        .padding(.top, 36)
                        .accessibilityAddTraits(.isHeader)
                    Text(app.voice.line("O-02"))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.silver)
                        .padding(.top, 12)
                        .padding(.horizontal, 10)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                Button(Literal.text("button.playAsGuest"), action: onPlayAsGuest)
                    .buttonStyle(.kedroPrimary)

                // Sign in with Apple (PRD §3.1). Signing in moves on through `onSignedIn` below.
                AppleSignInButton()

                #if DEBUG
                Button("Continue as Test User") {
                    auth.signInAsTestUser()
                }
                .font(.subheadline)
                .foregroundStyle(.silver)
                .frame(minHeight: 44)
                Button("Sign In as a Test Account") { isPickingTestAccount = true }
                    .font(.subheadline)
                    .foregroundStyle(.silver)
                    .frame(minHeight: 44)
                #endif

                Button(app.voice.line("O-04")) { isLearning = true }
                    .font(.footnote)
                    .foregroundStyle(.silverDim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                Button("Got a claim code?") { isClaiming = true }
                    .font(.footnote)
                    .foregroundStyle(.kedroRed)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onChange(of: auth.signedInUser != nil) { _, signedIn in
            if signedIn { onSignedIn() }
        }
        .sheet(isPresented: $isLearning) {
            NavigationStack {
                LearnView()
                    .appRouteDestinations()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Literal.text("button.done")) { isLearning = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isClaiming) {
            ClaimCodeSheet()
        }
        #if DEBUG
        .sheet(isPresented: $isPickingTestAccount) { DevAccountPicker() }
        #endif
    }
}

/// Guest path: first name only (O-03).
struct GuestNameStep: View {
    @Binding var name: String
    var onContinue: () -> Void

    @Environment(AppModel.self) private var app
    @FocusState private var isFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do people call you?")
                .kedroFont(.display)
                .foregroundStyle(.cream)
                .accessibilityAddTraits(.isHeader)
            TextField("First name", text: $name)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .focused($isFocused)
                .font(.title3)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(.surface, in: .rect(cornerRadius: 14))
                .onSubmit { if !trimmed.isEmpty { onContinue() } }
            Text(app.voice.line("O-03"))
                .font(.footnote)
                .foregroundStyle(.silver)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .safeAreaInset(edge: .bottom) {
            Button(Literal.text("button.continue"), action: onContinue)
                .buttonStyle(.kedroPrimary)
                .disabled(trimmed.isEmpty)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .onAppear { isFocused = true }
    }
}

/// "Pick a face" (mockup frame 3, O-11). Skippable: a random starter emoji is assigned.
struct FaceStep: View {
    @Binding var avatar: Avatar?
    var name: String
    var onContinue: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("Pick a Face")
                    .kedroFont(.display)
                    .foregroundStyle(.cream)
                    .accessibilityAddTraits(.isHeader)
                Text(app.voice.line("O-11"))
                    .font(.subheadline)
                    .foregroundStyle(.silver)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                AvatarPicker(avatar: $avatar, name: name)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button("Use This Face", action: onContinue)
                .buttonStyle(.kedroPrimary)
                .disabled(avatar == nil)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Skip") {
                    avatar = nil
                    onContinue()
                }
            }
        }
    }
}

/// "Your handle": a unique @handle suggested from the first name (design §5.1).
struct HandleStep: View {
    @Binding var text: String
    @Binding var accepted: Handle?
    var firstName: String
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Claim Your Handle")
                .kedroFont(.display)
                .foregroundStyle(.cream)
                .accessibilityAddTraits(.isHeader)
            Text("It's how people find you to add you to a table.")
                .foregroundStyle(.silver)
            HandleField(text: $text, accepted: $accepted, firstName: firstName)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .safeAreaInset(edge: .bottom) {
            Button(Literal.text("button.continue"), action: onContinue)
                .buttonStyle(.kedroPrimary)
                .disabled(accepted == nil)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }
}

#Preview("Welcome") {
    let model = AppModel.preview()
    model.preferences.hasCompletedOnboarding = false
    return OnboardingFlow()
        .previewEnvironment(model)
}

#Preview("Guest name") {
    @Previewable @State var name = ""
    NavigationStack {
        GuestNameStep(name: $name) {}
    }
    .previewEnvironment()
    .preferredColorScheme(.dark)
}

#Preview("Face") {
    @Previewable @State var avatar: Avatar? = .curated(.crow)
    NavigationStack {
        FaceStep(avatar: $avatar, name: "Noah") {}
    }
    .previewEnvironment()
    .preferredColorScheme(.dark)
}

#Preview("Handle") {
    @Previewable @State var text = ""
    @Previewable @State var accepted: Handle?
    NavigationStack {
        HandleStep(text: $text, accepted: $accepted, firstName: "Noah") {}
    }
    .previewEnvironment()
    .preferredColorScheme(.dark)
}
