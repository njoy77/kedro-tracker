import SwiftUI

/// "What You're In For": what Kedro does, before it asks for anything. Every row is a feature
/// that ships (rating and leaderboard, rivalries, badges and titles, receipts, live scores).
struct TourStep: View {
    var onContinue: () -> Void

    var body: some View {
        OnboardingPage(title: "What You're In For") {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingFeatureRow(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "Climb the Leaderboard",
                    detail: "Every finished game moves your rating. The board shows who's really on top."
                )
                OnboardingFeatureRow(
                    systemImage: "person.2",
                    title: "Rivalries",
                    detail: "A head-to-head record with everyone you play. Kedro remembers who leads."
                )
                OnboardingFeatureRow(
                    systemImage: "rosette",
                    title: "Badges and Titles",
                    detail: "Earned at the table, worn on your profile."
                )
                OnboardingFeatureRow(
                    systemImage: "receipt",
                    title: "Receipts",
                    detail: "Send the group chat proof of somebody's worst round."
                )
                OnboardingFeatureRow(
                    systemImage: "bolt",
                    title: "Live Scores, Math Included",
                    detail: "Enter each round and every phone at the table has the standings. Lock Screen too."
                )
            }
        } actions: {
            Button(Literal.text("button.continue"), action: onContinue)
                .buttonStyle(.kedroPrimary)
        }
    }
}

/// The age step: why Kedro asks (Spicy and Unhinged swear), then Declared Age Range only when
/// the player taps Share My Age Range. Every outcome moves on: under 18 locks the level picker to
/// Clean (O-10); not sharing, cancelling or an unavailable capability change nothing.
struct AgeStep: View {
    var onContinue: () -> Void

    var body: some View {
        OnboardingPage(title: "Kedro Has a Mouth") {
            VStack(alignment: .leading, spacing: 22) {
                Text("Every line comes in three strengths. Two of them swear, so they're for 18 and up.")
                    .foregroundStyle(.silver)
                OnboardingFeatureRow(
                    systemImage: "face.smiling",
                    title: "Clean",
                    detail: "Same attitude, zero swearing. Open to everyone."
                )
                OnboardingFeatureRow(
                    systemImage: "flame",
                    title: "Spicy and Unhinged",
                    detail: "18 and up. Under 18, it's Clean, and custom taunts stay off."
                )
                OnboardingFeatureRow(
                    systemImage: "lock",
                    title: "Just Which Side of 18",
                    detail: "Apple tells Kedro whether you're over or under 18. Never your birthday."
                )
            }
        } actions: {
            AgeRangeButton { _ in onContinue() }
            Button("Not Now", action: onContinue)
                .font(.subheadline)
                .foregroundStyle(.silver)
                .frame(minHeight: 44)
            Text("You can share it later in Settings.")
                .font(.footnote)
                .foregroundStyle(.silverDim)
        }
    }
}

/// The Local Network step: what finding the table gets you, then the system prompt only from
/// Find Tables Nearby. Denied: what stops working (tables nearby) and what still works (Join with
/// Code, QR codes), E-02. Not Now leaves discovery off until Play or Settings turns it on; the
/// table link of a live game still uses the local network, so iOS asks at the first table instead.
struct NearbyStep: View {
    var onContinue: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.openURL) private var openURL
    @State private var isAsking = false
    @State private var wasDenied = false

    var body: some View {
        OnboardingPage(title: wasDenied ? "Local Network Is Off" : "Find Your Table") {
            if wasDenied {
                VStack(alignment: .leading, spacing: 22) {
                    Text(app.voice.line("E-02"))
                        .foregroundStyle(.cream)
                    OnboardingFeatureRow(
                        systemImage: "qrcode",
                        title: "Still Works",
                        detail: "Join with Code and QR codes. The score syncs over the internet instead."
                    )
                    OnboardingFeatureRow(
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        title: "Won't Show Up",
                        detail: "Tables nearby on Play, and keeping score together with no internet."
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    OnboardingFeatureRow(
                        systemImage: "person.3",
                        title: "Sit Down, You're In",
                        detail: "Tables nearby show up on Play. Tap Sit Down and you're at the table. No code, no QR."
                    )
                    OnboardingFeatureRow(
                        systemImage: "wifi.slash",
                        title: "No Signal, No Problem",
                        detail: "Phones at the table keep the score in sync with each other, even without internet."
                    )
                    Text(app.voice.line("O-05"))
                        .font(.callout)
                        .foregroundStyle(.silver)
                }
            }
        } actions: {
            if wasDenied {
                Button(Literal.text("button.continue"), action: onContinue)
                    .buttonStyle(.kedroPrimary)
                Button("Open Settings") {
                    if let url = URL(string: "app-settings:") { openURL(url) }
                }
                .font(.subheadline)
                .foregroundStyle(.silver)
                .frame(minHeight: 44)
            } else {
                Button {
                    Task { await findTables() }
                } label: {
                    if isAsking { ProgressView() } else { Text("Find Tables Nearby") }
                }
                .buttonStyle(.kedroPrimary)
                .disabled(isAsking)
                Button("Not Now") {
                    prefs.nearbyDiscoveryEnabled = false
                    onContinue()
                }
                .font(.subheadline)
                .foregroundStyle(.silver)
                .frame(minHeight: 44)
                .disabled(isAsking)
                Text("Skip it and iOS asks when you first sit down at a table instead.")
                    .font(.footnote)
                    .foregroundStyle(.silverDim)
            }
        }
        .animation(.smooth, value: wasDenied)
        #if DEBUG
        .task { if DebugLaunch.tapsPrimary { await findTables() } }
        #endif
    }

    private func findTables() async {
        isAsking = true
        defer { isAsking = false }
        prefs.nearbyDiscoveryEnabled = true
        // No answer in time (the prompt left open) counts as a yes for now; Play checks again.
        if await LocalNetworkAccess.request() == .denied {
            wasDenied = true
        } else {
            onContinue()
        }
    }
}

// MARK: - Layout

/// An onboarding page: display title and scrolling content, with the actions pinned at the bottom.
struct OnboardingPage<Content: View, Actions: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .kedroFont(.display)
                    .foregroundStyle(.cream)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) { actions }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }
}

/// One feature on an onboarding page: a red symbol, a title and a line.
struct OnboardingFeatureRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.kedroRed)
                .frame(width: 34)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).kedroFont(.headline).foregroundStyle(.cream)
                Text(detail).font(.subheadline).foregroundStyle(.silver)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Tour") {
    NavigationStack { TourStep {} }
        .background(.night)
        .previewEnvironment()
        .preferredColorScheme(.dark)
}

#Preview("Age") {
    NavigationStack { AgeStep {} }
        .background(.night)
        .previewEnvironment()
        .preferredColorScheme(.dark)
}

#Preview("Nearby") {
    NavigationStack { NearbyStep {} }
        .background(.night)
        .previewEnvironment()
        .preferredColorScheme(.dark)
}
