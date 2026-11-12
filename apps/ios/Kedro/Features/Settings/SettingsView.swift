import SwiftUI

/// Settings (mockup frame 24): profile, account, language level, custom taunts, learner hints,
/// sounds (master switch, per-moment toggles with previews, table speaker), outbound images,
/// finding tables nearby, nearby alerts, and the rules.
///
/// Pushed with `AppRoute.settings`; doesn't create a NavigationStack.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppPreferences.self) private var prefs
    @Environment(AuthStore.self) private var auth
    @Environment(\.soundPreview) private var soundPreview
    @Environment(NetworkServices.self) private var network: NetworkServices?
    @State private var isClaiming = false
    #if DEBUG
    @State private var isPickingTestAccount = false
    #endif
    @State private var isConfirmingSignOut = false
    @State private var isLocalNetworkDenied = false

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

                // Declared Age Range, only from this tap (onboarding's age step is the other place).
                AgeRangeButton(title: "Share Age Range", isProminent: false) { outcome in
                    if let message = Self.message(for: outcome) { app.toasts.show(message) }
                }
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
                Toggle("Share images in Clean", isOn: $prefs.outboundImagesClean)
            } header: {
                Text("Sharing")
            } footer: {
                Text("Receipts and share cards go to people who didn't pick a level. Turn this off to send them in yours.")
            }

            Section {
                Toggle("Find Tables Nearby", isOn: $prefs.nearbyDiscoveryEnabled)
            } header: {
                Text("Nearby")
            } footer: {
                if prefs.nearbyDiscoveryEnabled, isLocalNetworkDenied {
                    Text(app.voice.line("E-02"))
                } else {
                    Text("Phones at the same table find each other, so nobody types a code. Join with Code and QR codes work either way.")
                }
            }
            // Turning it on is the explicit tap that may show the Local Network prompt (the first
            // time); after that this only checks.
            .task(id: prefs.nearbyDiscoveryEnabled) {
                guard prefs.nearbyDiscoveryEnabled, !(app.discovery is NoNearbyTables) else {
                    isLocalNetworkDenied = false
                    return
                }
                isLocalNetworkDenied = await LocalNetworkAccess.request() == .denied
            }

            Section {
                Toggle("Tables nearby", isOn: $prefs.nearbyAlertsEnabled)
                    .onChange(of: prefs.nearbyAlertsEnabled) { _, isOn in
                        guard isOn, let push = network?.push else { return }
                        // The footer (J-14) is the primer; the system asks next. Turning it on also
                        // starts the Bluetooth beacon and scan (NetworkServices follows the switch).
                        Task {
                            if await !push.requestAuthorization() { prefs.nearbyAlertsEnabled = false }
                        }
                    }
            } header: {
                Text("Notifications")
            } footer: {
                Text(app.voice.line("J-14"))
            }

            Section("Rules") {
                NavigationLink(value: AppRoute.learn) { Label("How to Play", systemImage: "graduationcap") }
                NavigationLink(value: AppRoute.rules) { Label("Rules", systemImage: "book") }
                NavigationLink(value: AppRoute.knockCalculator(nil)) { Label("Knock Calculator", systemImage: "function") }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $isClaiming) { ClaimCodeSheet() }
        #if DEBUG
        .sheet(isPresented: $isPickingTestAccount) { DevAccountPicker() }
        #endif
        .confirmationDialog("Sign out of Kedro?", isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { try? await auth.signOut() }
            }
        } message: {
            Text("Your games stay on this phone and on your account.")
        }
    }

    /// A toast for a Share Age Range answer (under 18 shows in the Language footer, O-10).
    private static func message(for outcome: AgeRangeOutcome) -> String? {
        switch outcome {
        case .under18: nil
        case .adult: "18 or over. Every level's open."
        case .notShared: "Not shared. Nothing changed."
        case .unavailable: "Age range isn't available on this iPhone."
        }
    }

    // MARK: Profile and account

    @ViewBuilder
    private var profileSection: some View {
        if let profile = app.profile {
            Section {
                NavigationLink(value: AppRoute.editProfile) {
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
                // A guest signing in keeps their history: `AppModel.didSignIn` claims it.
                AppleSignInButton()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                #if DEBUG
                Button("Continue as Test User") { auth.signInAsTestUser() }
                Button("Sign In as a Test Account") { isPickingTestAccount = true }
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

#Preview("Settings") {
    NavigationStack { SettingsView().appRouteDestinations() }
        .previewEnvironment()
        .environment(\.soundPreview, SoundPreviewAction { _ in })
}

#Preview("Under 18") {
    let model = AppModel.preview()
    model.preferences.isUnder18 = true
    return NavigationStack { SettingsView().appRouteDestinations() }
        .previewEnvironment(model)
}
