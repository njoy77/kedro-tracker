import Foundation

/// Literal widget strings that aren't in the copy deck yet. The extension doesn't compile the
/// deck (it would pull in the whole voice system), and these are literal: identical in every
/// language level.
/// TODO(copy): add these to `docs/kedro-ios-copy.md` §20 (literal) so the deck owns them.
nonisolated enum WidgetCopy {
    static let standing = "Standing"
    static let rivalry = "Rivalry"
    static let nextBadge = "Next Badge"
    static let notRanked = "Not ranked yet"
    static let noRival = "Play a few games. Somebody will start to bother you."
    static let noBadge = "Every badge is yours. Go outside."
    static let you = "You"
    static let global = "Global"

    static let standingDescription = "Your rank, rating and how you moved this week."
    static let rivalryDescription = "You against the person you play most."
    static let nextBadgeDescription = "The badge you're closest to."

    /// "3 of 5" (the copy deck's `label.meter`).
    static func meter(_ n: Int) -> String { "\(n) of \(StandingSnapshot.gamesToRank)" }

    /// "▲ 2 this week" reads "Up 2 this week" (the arrow is a glyph, not the only cue).
    static func movement(_ places: Int) -> String {
        places == 0 ? "Same as last week" : "\(abs(places)) this week"
    }

    static func movementAccessibility(_ places: Int) -> String {
        switch places {
        case 0: "Same as last week"
        case 1...: "Up \(places) this week"
        default: "Down \(-places) this week"
        }
    }
}

/// Literal Live Activity strings that aren't in the copy deck.
nonisolated enum LiveActivityCopy {
    /// The red tag on the Lock Screen header (mockup 18).
    static let live = "LIVE"
}
