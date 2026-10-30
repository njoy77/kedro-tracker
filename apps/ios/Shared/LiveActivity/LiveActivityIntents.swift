import AppIntents
import Foundation

/// What a Live Activity button asks the app to do. JSON: `"recordRound"` | `"reportHand"` | `"openTable"`.
nonisolated enum LiveActivityAction: String, Codable, Hashable, Sendable, CaseIterable {
    /// Scorekeeper mode: open the Table with the Round sheet up.
    case recordRound
    /// Self-report mode: open the Table with Report Your Hand up.
    case reportHand
    /// Just open the Table (tapping the activity itself).
    case openTable
}

/// A button tap waiting for the app: which game, which action, when.
nonisolated struct LiveActivityActionRequest: Codable, Hashable, Sendable {
    /// Requests older than this are dropped (the person has moved on).
    static let lifetime: TimeInterval = 120

    var action: LiveActivityAction
    /// `GameID` as a lowercase UUID string.
    var gameID: String
    var requestedAt: Date

    func isExpired(now: Date = .now) -> Bool {
        now.timeIntervalSince(requestedAt) > Self.lifetime
    }
}

/// Hands Live Activity button taps to the app.
///
/// The intents below are compiled into the app and the widget extension; the system runs a
/// `LiveActivityIntent` in the app's process and brings the app forward (`supportedModes`). The
/// request is written to the app group first, so it survives a cold launch, and then handed to
/// `handler` if the app installed one (`LiveActivityController` does).
@MainActor
enum LiveActivityActionInbox {
    private static let key = "liveActivity.pendingAction"

    /// Installed by the app at launch. nil in the extension and the clip.
    static var handler: ((LiveActivityActionRequest) -> Void)?

    static func post(_ request: LiveActivityActionRequest, defaults: UserDefaults = KedroAppGroup.defaults) {
        if let data = try? SharedJSON.encoder().encode(request) {
            defaults.set(data, forKey: key)
        }
        if let handler {
            defaults.removeObject(forKey: key)
            handler(request)
        }
    }

    /// The pending request, if a fresh one is waiting. Removes it.
    static func take(now: Date = .now, defaults: UserDefaults = KedroAppGroup.defaults) -> LiveActivityActionRequest? {
        guard let data = defaults.data(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        guard let request = try? SharedJSON.decoder().decode(LiveActivityActionRequest.self, from: data),
              !request.isExpired(now: now)
        else { return nil }
        return request
    }
}

/// "Record Round 6" on the Live Activity (scorekeeper mode).
struct RecordRoundIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Record Round"
    static let description = IntentDescription("Opens the table with the Round sheet up.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let isDiscoverable = false

    @Parameter(title: "Game")
    var gameID: String

    init() {}

    init(gameID: String) {
        self.gameID = gameID
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityActionInbox.post(LiveActivityActionRequest(action: .recordRound, gameID: gameID, requestedAt: .now))
        return .result()
    }
}

/// "Report Your Hand" on the Live Activity (self-report mode).
struct ReportHandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Report Your Hand"
    static let description = IntentDescription("Opens the table with Report Your Hand up.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let isDiscoverable = false

    @Parameter(title: "Game")
    var gameID: String

    init() {}

    init(gameID: String) {
        self.gameID = gameID
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityActionInbox.post(LiveActivityActionRequest(action: .reportHand, gameID: gameID, requestedAt: .now))
        return .result()
    }
}
