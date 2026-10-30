@preconcurrency import DeclaredAgeRange
import OSLog
import SwiftUI

/// Asks Declared Age Range whether the player is under 18 (design §4.1, §8.3) and records it in
/// `AppPreferences.isUnder18`, which locks Clean and turns custom taunts off.
///
/// Uses SwiftUI's `requestAgeRange` action, which needs a view to present from, so it runs from
/// the level picker (first launch) and Settings rather than from `AppModel.start()`. If the person
/// declines, or the capability isn't available (no entitlement, simulator), nothing changes.
struct AgeRangeCheck: ViewModifier {
    @Environment(\.requestAgeRange) private var requestAgeRange
    @Environment(AppPreferences.self) private var prefs

    private static let log = Logger(subsystem: "com.njoy77.kedro", category: "AgeRange")

    func body(content: Content) -> some View {
        content.task {
            do {
                switch try await requestAgeRange(ageGates: 18) {
                case .sharing(let range):
                    if let upper = range.upperBound, upper < 18 {
                        prefs.isUnder18 = true
                    } else if let lower = range.lowerBound, lower >= 18 {
                        prefs.isUnder18 = false
                    }
                case .declinedSharing:
                    break
                @unknown default:
                    break
                }
            } catch {
                Self.log.info("Age range unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension View {
    /// Checks Declared Age Range once when the view appears.
    func checksAgeRange() -> some View {
        modifier(AgeRangeCheck())
    }
}
