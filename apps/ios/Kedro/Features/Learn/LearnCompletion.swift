import Foundation

/// Tracks the two halves of Learn (the cards with the knock quiz, and the Score a Round drill).
/// Once both are done it sets `LearningProgress.didTheReadingKey`, which Core/Stats reads to award
/// Did the Reading (design §12.6).
nonisolated enum LearnCompletion {
    enum Part: String, CaseIterable, Sendable {
        case cards = "kedro.learn.cardsDone"
        case drill = "kedro.learn.drillDone"
    }

    static func mark(_ part: Part, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: part.rawValue)
        if Part.allCases.allSatisfy({ defaults.bool(forKey: $0.rawValue) }) {
            defaults.set(true, forKey: LearningProgress.didTheReadingKey)
        }
    }
}
