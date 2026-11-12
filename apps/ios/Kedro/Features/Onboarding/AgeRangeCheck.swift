@preconcurrency import DeclaredAgeRange
import OSLog
import SwiftUI

/// What a Declared Age Range request came back with (design §4.1, §8.3).
nonisolated enum AgeRangeOutcome: Sendable, Equatable {
    /// Shared, and under 18: Clean is locked and custom taunts are off.
    case under18
    /// Shared, and 18 or over.
    case adult
    /// Declined, cancelled, or shared a range that doesn't say which side of 18.
    case notShared
    /// The capability isn't available (no entitlement, the Simulator, an unsupported region).
    case unavailable

    /// The outcome for a shared range (Apple's bounds, either of which may be open).
    init(lowerBound: Int?, upperBound: Int?) {
        if let upperBound, upperBound < 18 {
            self = .under18
        } else if let lowerBound, lowerBound >= 18 {
            self = .adult
        } else {
            self = .notShared
        }
    }

    /// Records a shared answer in `AppPreferences.isUnder18`. Not sharing changes nothing, so an
    /// earlier answer (and its Clean lock) stands.
    @MainActor func apply(to prefs: AppPreferences) {
        switch self {
        case .under18: prefs.isUnder18 = true
        case .adult: prefs.isUnder18 = false
        case .notShared, .unavailable: break
        }
    }
}

/// The only place Kedro asks for an age range: a button, so the system sheet never shows up
/// unexplained (onboarding's age step and Settings → Language). Uses SwiftUI's `requestAgeRange`
/// action, which needs a view to present from. Records the answer, then reports it.
struct AgeRangeButton: View {
    var title: LocalizedStringKey = "Share My Age Range"
    /// The kedroPrimary capsule (onboarding) or a plain row (Settings).
    var isProminent = true
    var onResult: (AgeRangeOutcome) -> Void = { _ in }

    @Environment(\.requestAgeRange) private var requestAgeRange
    @Environment(AppPreferences.self) private var prefs
    @State private var isAsking = false

    private static let log = Logger(subsystem: "com.njoy77.kedro", category: "AgeRange")

    var body: some View {
        let button = Button {
            Task { await ask() }
        } label: {
            if isAsking {
                ProgressView()
            } else {
                Text(title)
            }
        }
        .disabled(isAsking)

        if isProminent {
            button.buttonStyle(.kedroPrimary)
                #if DEBUG
                .task { if DebugLaunch.tapsPrimary { await ask() } }
                #endif
        } else {
            button
        }
    }

    private func ask() async {
        isAsking = true
        defer { isAsking = false }
        let outcome: AgeRangeOutcome
        do {
            switch try await requestAgeRange(ageGates: 18) {
            case .sharing(let range):
                outcome = AgeRangeOutcome(lowerBound: range.lowerBound, upperBound: range.upperBound)
            case .declinedSharing:
                outcome = .notShared
            @unknown default:
                outcome = .notShared
            }
        } catch {
            Self.log.info("Age range unavailable: \(error.localizedDescription, privacy: .public)")
            outcome = .unavailable
        }
        outcome.apply(to: prefs)
        onResult(outcome)
    }
}

#Preview {
    VStack(spacing: 16) {
        AgeRangeButton()
        AgeRangeButton(title: "Check Age Range", isProminent: false)
    }
    .padding()
    .background(.night)
    .previewEnvironment()
}
