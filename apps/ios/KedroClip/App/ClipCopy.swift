import Foundation

/// App Clip strings from mockup frame 20 that aren't in the copy deck yet. Informational and
/// literal (identical in every level). Voice lines come from the deck: J-13 (which seat) and
/// F-04 (offline).
/// TODO(copy): add these to `docs/kedro-ios-copy.md` (§5.8 App Clip) so the deck owns them.
nonisolated enum ClipCopy {
    static let badge = "App Clip"
    static let thatsMe = "That's me"
    static let scanPrompt = "Scan the code at the table to sit down."
    static let footer = "You'll see the live scores and can report your own hand. This needs internet."
    static let getKedro = "Get Kedro to keep this"
    static let getKedroSubline = "Your games come with you. Automatically."
    static let get = "Get"
    static let tryAgain = "Try Again"
    static let iKnocked = "I knocked"
    static let everyone = "Everyone"
    static let reported = "Hand in. Waiting on the table."
    static let watching = "Watching"

    static func notListed(host: String) -> String { "Not on the list? Ask \(host) to add you." }
    static func expired(host: String) -> String { "That code expired. Ask \(host) to show it again." }
    static func gamesWith(_ games: Int, host: String) -> String {
        games == 1 ? "1 game with \(host)" : "\(games) games with \(host)"
    }

    /// "You finished 5th · 70".
    static func result(ordinal: String, total: String) -> String { "You finished \(ordinal) · \(total)" }
}
