import SwiftUI

/// Settings (mockup frame 24): profile, account, language level, custom taunts, learner hints,
/// sounds (master switch, per-moment toggles with previews, table speaker), outbound images,
/// nearby alerts, and the rules.
///
/// Pushed with `AppRoute.settings`; doesn't create a NavigationStack.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppPreferences.self) private var prefs
    @Environment(AuthStore.self) private var auth
    @Environment(\.soundPreview) private var soundPreview
    @AppStorage(SettingsKeys.outboundImagesClean) private var outboundImagesClean = SettingsKeys.outboundImagesCleanDefault
    @State private var isClaiming = false
    @State private var isConfirmingSignOut = false

    var body: some View {
        @Bindable var prefs = prefs
        @Bindable var sounds = prefs.sounds

        Form {
            profileSection
            accountSection

            Section {
                Picker("Level", selection: $prefs.languageLevel) {
                    ForEach(LanguageLevel.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(prefs.isUnder18)
                .accessibilityLabel("Language level")

                Toggle("Custom taunts", isOn: $prefs.customTauntsEnabled)
                    .disabled(prefs.isUnder18)
            } header: {
                Text("Language")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if prefs.isUnder18 {
                        Text(app.voice.line("O-10"))
                    } else {
                        Text(prefs.languageLevel.settingsDescription)
                    }
                    Text(app.voice.line("S-02"))
                }
            }

            Section {
                Picker("Learner hints", selection: $prefs.learnerHints) {
                    ForEach(LearnerHints.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("A teaching line instead of a roast when your own knock goes wrong.")
            }

            soundsSection(sounds: sounds)

            Section {
                Toggle("Share images in Clean", isOn: $outboundImagesClean)
            } header: {
                Text("Sharing")
            } footer: {
                Text("Receipts and share cards go to people who didn't pick a level. Turn this off to send them in yours.")
            }

            Section {
                Toggle("Tables nearby", isOn: $prefs.nearbyAlertsEnabled)
            } header: {
                Text("Notifications")
            } footer: {
                // TODO(networking/push): request notification permission (with a primer) when this
                // turns on, and start the background scan (design §5.4).
                Text(app.voice.line("J-14"))
            }

            Section("Rules") {
                NavigationLink(value: AppRoute.learn) { Label("Learn Cambio", systemImage: "graduationcap") }
                NavigationLink(value: AppRoute.rules) { Label("Rules", systemImage: "book") }
                NavigationLink(value: AppRoute.knockCalculator(nil)) { Label("Knock Calculator", systemImage: "function") }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .navigationTitle("Settings")
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .profile: ProfileEditView()
            }
        }
        .sheet(isPresented: $isClaiming) { ClaimCodeSheet() }
        .confirmationDialog("Sign out of Kedro?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { try? await auth.signOut() }
            }
        } message: {
            Text("Your games stay on this phone and on your account.")
        }
        .checksAgeRange()
    }

    // MARK: Profile and account

    @ViewBuilder
    private var profileSection: some View {
        if let profile = app.profile {
            Section {
                NavigationLink(value: SettingsRoute.profile) {
                    HStack(spacing: 14) {
                        AvatarView(avatar: profile.avatar, name: profile.displayName, isGuest: profile.isGuest, size: .standings)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName).foregroundStyle(.cream)
                            Text(profile.handle?.description ?? (profile.isGuest ? "Guest on this phone" : "No handle yet"))
                                .font(.footnote)
                                .foregroundStyle(.silver)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if auth.signedInUser != nil {
                if let email = auth.email {
                    LabeledContent("Signed in", value: email)
                }
                Button("Sign Out", role: .destructive) { isConfirmingSignOut = true }
            } else {
                SignInWithAppleSoon()
                #if DEBUG
                Button("Continue as Test User") { auth.signInAsTestUser() }
                #endif
            }
            Button("Got a claim code?") { isClaiming = true }
        } header: {
            Text("Account")
        } footer: {
            if auth.signedInUser == nil, app.profile?.isGuest == true {
                Text(app.voice.line("O-03"))
            }
        }
    }

    // MARK: Sounds

    private func soundsSection(sounds: SoundSettings) -> some View {
        Section {
            Toggle(isOn: Binding(get: { sounds.isEnabled }, set: { on in
                sounds.isEnabled = on
                if on { app.toasts.show(app.voice.line("SN-03")) }
            })) {
                HStack(spacing: 6) {
                    Text("Sound pack")
                    Text("· Classic").foregroundStyle(.silverDim)
                }
            }

            ForEach(SoundMoment.allCases) { moment in
                SoundMomentRow(moment: moment, sounds: sounds, preview: soundPreview)
            }

            Picker("Table speaker", selection: Binding(get: { sounds.tableSpeaker }, set: { sounds.tableSpeaker = $0 })) {
                ForEach(TableSpeakerPreference.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Sounds")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(app.voice.line("SN-02"))
                Text(app.voice.line("SN-01"))
            }
        }
    }
}

/// Feature-internal pushes from Settings.
enum SettingsRoute: Hashable {
    case profile
}

/// One sound: preview, what it is, and its toggle (dimmed while the master switch is off).
private struct SoundMomentRow: View {
    let moment: SoundMoment
    let sounds: SoundSettings
    let preview: SoundPreviewAction?

    var body: some View {
        HStack(spacing: 12) {
            if let preview {
                Button("Play \(moment.title)", systemImage: "play.fill") { preview(moment) }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.kedroRed)
                    .buttonStyle(.borderless)
                    .frame(width: 44, height: 44)
            }
            Toggle(isOn: Binding(get: { sounds.isOn(moment) }, set: { sounds.set(moment, on: $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.title)
                    Text(moment.detail).font(.footnote).foregroundStyle(.silver)
                }
            }
        }
        .opacity(sounds.isEnabled ? 1 : 0.5)
    }
}

/// Sign in with Apple, shown dimmed while the developer account is pending (PRD §3.1).
struct SignInWithAppleSoon: View {
    var body: some View {
        Label("Sign in with Apple · Soon", systemImage: "applelogo")
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.white, in: .capsule)
            .opacity(0.4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sign in with Apple, coming soon")
            .accessibilityAddTraits(.isButton)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
    }
}

#Preview("Settings") {
    NavigationStack { SettingsView() }
        .previewEnvironment()
        .environment(\.soundPreview, SoundPreviewAction { _ in })
}

#Preview("Under 18") {
    let model = AppModel.preview()
    model.preferences.isUnder18 = true
    return NavigationStack { SettingsView() }
        .previewEnvironment(model)
}
