import Foundation

/// Answers "is this person under 18?" for the Clean lock and custom-taunt switch-off
/// (design §4.1, §8.3). The real answer comes from Apple's Declared Age Range; the Lobby agent
/// (Onboarding) provides that implementation and assigns it to `AppModel.ageRange`.
protocol AgeRangeProviding: Sendable {
    /// true if under 18, false if 18 or over, nil if the person declined or it's unknown.
    func isUnder18() async -> Bool?
}

/// Nothing declared: treated as an adult unless `AppPreferences.isUnder18` was set otherwise.
nonisolated struct UndeclaredAgeRange: AgeRangeProviding {
    func isUnder18() async -> Bool? { nil }
}
