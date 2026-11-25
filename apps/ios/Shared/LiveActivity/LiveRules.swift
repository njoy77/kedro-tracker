import ActivityKit
import AppIntents
import Foundation

/// The rules cheat sheet on the Lock Screen (design §13.2): card values, power cards and knock
/// scoring, one tap away without unlocking. Literal, like every rules text (it doesn't change with
/// the language level), and it must agree with Learn → Rules (`RulesContent`, pinned by
/// `LiveRulesTests`).
///
/// Whether it's showing is this phone's own choice, so it isn't in the server's broadcasts: the
/// Rules button writes it to the app group for the round being played, and the Lock Screen reads
/// it back whenever it redraws. Taunts, neighs and the app's heartbeat leave it open; the next
/// round (or the Scores button) closes it.
nonisolated enum LiveRules {
    struct Line: Hashable, Sendable, Identifiable {
        /// "Values" (uppercased by the label style).
        let label: String
        let text: String

        var id: String { label }
    }

    static let lines: [Line] = [
        Line(label: "Values", text: "A 1 · 2–10 face · J 11 · Q 12 · K♠♣ 13 · K♥♦ \u{2212}1 · Joker 0"),
        Line(label: "Powers", text: "7–8 peek yours · 9–10 peek theirs · J/Q blind swap · K♠♣ look, then swap"),
        Line(label: "Knock", text: "Lowest \u{2212}10 · Tied: your hand · Beaten: your hand + 10"),
    ]

    /// VoiceOver reads the whole sheet as one element.
    static var accessibilityLabel: String {
        lines.map { "\($0.label): \($0.text)" }.joined(separator: ". ")
    }

    // MARK: Open or closed

    private static let key = "liveActivity.rulesOpen"

    private struct Open: Codable, Hashable {
        var gameID: String
        var round: Int
    }

    /// Whether the sheet is open for this game's round.
    static func isOpen(gameID: String, round: Int, defaults: UserDefaults = KedroAppGroup.defaults) -> Bool {
        guard let data = defaults.data(forKey: key), let open = try? JSONDecoder().decode(Open.self, from: data) else { return false }
        return open.gameID == gameID && open.round == round
    }

    static func setOpen(_ isOpen: Bool, gameID: String, round: Int, defaults: UserDefaults = KedroAppGroup.defaults) {
        if isOpen, let data = try? JSONEncoder().encode(Open(gameID: gameID, round: round)) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Opens or closes the sheet on this game's Live Activity and redraws it now. Runs from the
    /// Rules button, in whichever process the system runs the intent in (ActivityKit updates
    /// work in the widget extension too).
    static func show(_ isOpen: Bool, gameID: String, defaults: UserDefaults = KedroAppGroup.defaults) async {
        // `Activity` isn't Sendable: look it up and update it in the same context.
        for activity in Activity<LiveGameAttributes>.activities where activity.attributes.gameID == gameID {
            var state = activity.content.state
            setOpen(isOpen, gameID: gameID, round: state.roundNumber, defaults: defaults)
            state.showsRules = isOpen
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate, relevanceScore: activity.content.relevanceScore))
        }
    }
}

extension LiveGameAttributes.ContentState {
    /// Whether this phone shows the rules instead of the standings: the Rules button's own
    /// update says so directly; any later content (a broadcast, the heartbeat) goes by what the
    /// button saved for this round.
    func showsRules(gameID: String, defaults: UserDefaults = KedroAppGroup.defaults) -> Bool {
        guard phase == .active else { return false }
        return showsRules ?? LiveRules.isOpen(gameID: gameID, round: roundNumber, defaults: defaults)
    }
}

/// "Rules" / "Scores" on the Live Activity: flips the Lock Screen between the standings and the
/// cheat sheet, without unlocking or opening Kedro.
struct ShowRulesIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Show Rules"
    static let description = IntentDescription("Shows card values, power cards and knock scoring on the Lock Screen.")
    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false

    @Parameter(title: "Game")
    var gameID: String

    @Parameter(title: "Show")
    var isOpen: Bool

    init() {}

    init(gameID: String, isOpen: Bool) {
        self.gameID = gameID
        self.isOpen = isOpen
    }

    func perform() async throws -> some IntentResult {
        await LiveRules.show(isOpen, gameID: gameID)
        return .result()
    }
}
