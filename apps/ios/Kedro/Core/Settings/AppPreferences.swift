import Foundation
import Observation

/// Per-phone preferences, persisted in `UserDefaults` under `AppPreferences.Key`. The keys are
/// public so a view can also bind with `@AppStorage(AppPreferences.Key.languageLevel)`, but
/// prefer reading `@Environment(AppPreferences.self)` so every screen updates together.
@Observable
final class AppPreferences {
    nonisolated enum Key {
        static let languageLevel = "kedro.languageLevel"
        static let isUnder18 = "kedro.isUnder18"
        static let customTauntsEnabled = "kedro.customTauntsEnabled"
        static let learnerHints = "kedro.learnerHints"
        static let prefersCardMode = "kedro.prefersCardMode"
        static let lastPlannedRounds = "kedro.lastPlannedRounds"
        static let lastScoringMode = "kedro.lastScoringMode"
        static let hasCompletedOnboarding = "kedro.hasCompletedOnboarding"
        static let nearbyAlertsEnabled = "kedro.nearbyAlertsEnabled"
        static let lastLookedAt = "kedro.lastLookedAt"
        static let outboundImagesClean = "kedro.outboundImagesClean"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// The player's chosen level. Read `effectiveLanguageLevel` to render.
    var languageLevel: LanguageLevel {
        didSet { defaults.set(languageLevel.rawValue, forKey: Key.languageLevel) }
    }

    /// Set from Declared Age Range (`AppModel.ageRange`). Locks Clean and turns custom taunts off.
    var isUnder18: Bool {
        didSet { defaults.set(isUnder18, forKey: Key.isUnder18) }
    }

    /// Receive and send custom taunts (Settings → S-02). Canned taunts are always on.
    var customTauntsEnabled: Bool {
        didSet { defaults.set(customTauntsEnabled, forKey: Key.customTauntsEnabled) }
    }

    /// Teaching lines instead of roasts for your own bad outcomes (design §4.3).
    var learnerHints: LearnerHints {
        didSet { defaults.set(learnerHints.rawValue, forKey: Key.learnerHints) }
    }

    /// Card mode vs the number pad, remembered per user (design §7.3). nil until chosen; Card
    /// mode is the default for a player's first 3 games.
    var prefersCardMode: Bool? {
        didSet {
            if let prefersCardMode { defaults.set(prefersCardMode, forKey: Key.prefersCardMode) }
            else { defaults.removeObject(forKey: Key.prefersCardMode) }
        }
    }

    /// The lobby's Rounds default ("last time's").
    var lastPlannedRounds: Int {
        didSet { defaults.set(lastPlannedRounds, forKey: Key.lastPlannedRounds) }
    }

    /// The lobby's Scoring default.
    var lastScoringMode: ScoringMode {
        didSet { defaults.set(lastScoringMode.rawValue, forKey: Key.lastScoringMode) }
    }

    /// The onboarding gate in `RootView`. Set by `OnboardingFlow` when it finishes.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// Opt-in "your people started a table nearby" (design §5.4).
    var nearbyAlertsEnabled: Bool {
        didSet { defaults.set(nearbyAlertsEnabled, forKey: Key.nearbyAlertsEnabled) }
    }

    /// When the player last saw Play's "Since you last looked".
    var lastLookedAt: Date? {
        didSet { defaults.set(lastLookedAt, forKey: Key.lastLookedAt) }
    }

    /// Outbound images (receipts, share cards, Wrapped) render Clean by default, because the
    /// group chat didn't opt in (design §8.5, §12.9). Off: they use this player's level.
    var outboundImagesClean: Bool {
        didSet { defaults.set(outboundImagesClean, forKey: Key.outboundImagesClean) }
    }

    /// Sound pack settings.
    let sounds: SoundSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        languageLevel = defaults.string(forKey: Key.languageLevel).flatMap(LanguageLevel.init(rawValue:)) ?? .adultDefault
        isUnder18 = defaults.bool(forKey: Key.isUnder18)
        customTauntsEnabled = defaults.object(forKey: Key.customTauntsEnabled) as? Bool ?? true
        learnerHints = defaults.string(forKey: Key.learnerHints).flatMap(LearnerHints.init(rawValue:)) ?? .automatic
        prefersCardMode = defaults.object(forKey: Key.prefersCardMode) as? Bool
        let rounds = defaults.integer(forKey: Key.lastPlannedRounds)
        lastPlannedRounds = GameConfig.plannedRoundsRange.contains(rounds) ? rounds : GameConfig.defaultPlannedRounds
        lastScoringMode = defaults.string(forKey: Key.lastScoringMode).flatMap(ScoringMode.init(rawValue:)) ?? .scorekeeper
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        nearbyAlertsEnabled = defaults.bool(forKey: Key.nearbyAlertsEnabled)
        lastLookedAt = defaults.object(forKey: Key.lastLookedAt) as? Date
        outboundImagesClean = defaults.object(forKey: Key.outboundImagesClean) as? Bool ?? true
        sounds = SoundSettings(defaults: defaults)
    }

    /// The level to render this player's personal surfaces in: Clean when under 18.
    var effectiveLanguageLevel: LanguageLevel { isUnder18 ? .clean : languageLevel }

    /// The level an outbound image renders in: Clean unless the player turned that off.
    var outboundImageLevel: LanguageLevel { outboundImagesClean ? .clean : effectiveLanguageLevel }

    /// Custom taunts are off (both ways) under 18.
    var effectiveCustomTaunts: Bool { customTauntsEnabled && !isUnder18 }

    /// Whether a player with `gamesPlayed` finished games gets learner lines.
    func showsLearnerHints(gamesPlayed: Int) -> Bool {
        switch learnerHints {
        case .automatic: gamesPlayed < 3
        case .on: true
        case .off: false
        }
    }
}

/// Learner hints: automatic for the first 3 games, or forced on/off.
nonisolated enum LearnerHints: String, Hashable, Sendable, CaseIterable {
    case automatic, on, off

    /// Literal Settings label.
    var title: String {
        switch self {
        case .automatic: "First 3 Games"
        case .on: "Always"
        case .off: "Off"
        }
    }
}
