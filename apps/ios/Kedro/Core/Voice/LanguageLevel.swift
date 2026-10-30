import Foundation

/// How much Kedro swears (design §4.1, copy deck §3). Ordered: clean < spicy < unhinged.
/// JSON / `UserDefaults`: `"clean"` | `"spicy"` | `"unhinged"`.
nonisolated enum LanguageLevel: String, Hashable, Sendable, Codable, CaseIterable, Comparable, Identifiable {
    case clean, spicy, unhinged

    var id: String { rawValue }

    /// "Clean", "Spicy", "Unhinged" (literal).
    var displayName: String { rawValue.capitalized }

    /// The Settings description (copy deck §3, `S-01`).
    var settingsDescription: String {
        switch self {
        case .clean: "Clean: same attitude, zero swearing. For game night at your in-laws'."
        case .spicy: "Spicy: swears when it counts."
        case .unhinged: "Unhinged: no filter. Your friends will be called names. Lovingly."
        }
    }

    /// The short line on the level picker cards (mockup frame 2).
    var shortDescription: String {
        switch self {
        case .clean: "Same attitude, zero swearing."
        case .spicy: "Swears when it counts."
        case .unhinged: "No filter. Your friends will be called names. Lovingly."
        }
    }

    /// The default for adults at first launch (design §5.1).
    static let adultDefault = LanguageLevel.unhinged

    private var order: Int {
        switch self {
        case .clean: 0
        case .spicy: 1
        case .unhinged: 2
        }
    }

    static func < (lhs: LanguageLevel, rhs: LanguageLevel) -> Bool { lhs.order < rhs.order }

    /// The house voice for shared surfaces at a table: the lowest level of anyone seated, further
    /// lowered by the host's cap (design §4.1). Kedro never says who lowered it.
    static func house(seated levels: some Sequence<LanguageLevel>, cap: LanguageLevel? = nil) -> LanguageLevel {
        var lowest = levels.min() ?? .unhinged
        if let cap { lowest = min(lowest, cap) }
        return lowest
    }
}
