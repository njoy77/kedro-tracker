import ActivityKit
import Foundation
import Observation
import OSLog

/// Runs the live game's Live Activity (design §13.2, §11 "Live Activity offline").
///
/// - Starts it at Deal (the game turns `active`), on phones seated at the table or watching it.
/// - Updates it locally on every folded change while Kedro runs, plus a heartbeat every minute
///   that pushes `staleDate` (3 minutes) forward. When Kedro is suspended the heartbeat stops,
///   so after 3 minutes without news the activity dims and shows N-06.
/// - Ends it at the finish (kept on the Lock Screen for 15 minutes) or immediately on abandon.
/// - Online updates while suspended come from the server over a per-game APNs broadcast
///   channel: install `channelProvider` (and `onPushToStartToken`) to turn them on.
/// - Its buttons (`RecordRoundIntent`, `ReportHandIntent`) land in `pendingAction`; the Table
///   takes it with `takePendingAction(for:)` and opens the Round sheet or Report Your Hand.
///
/// Installed once by `.liveGameActivity()` and reachable from the environment as an optional:
/// `@Environment(LiveActivityController.self) private var liveActivity: LiveActivityController?`.
@Observable
final class LiveActivityController {
    /// Content older than this without an update is stale (design §11).
    static let staleInterval: TimeInterval = 3 * 60
    /// How often a running app re-confirms the content.
    static let heartbeatInterval: Duration = .seconds(60)
    /// How long a finished game stays on the Lock Screen.
    static let finishedDismissalDelay: TimeInterval = 15 * 60
    /// With no live game at launch, wait this long before ending leftover activities (a game
    /// may still be resuming).
    static let orphanGracePeriod: Duration = .seconds(5)

    /// A Live Activity button tap waiting for the Table.
    private(set) var pendingAction: LiveActivityActionRequest?

    /// Whether the app is in the foreground (set by `.liveGameActivity()` from the scene phase).
    /// The self-report alert (N-05) only plays while it isn't.
    var isAppActive = true {
        didSet {
            if isAppActive, !oldValue { Task { await refresh() } }
        }
    }

    /// Returns the APNs broadcast channel ID for a game, created by the backend, so the server
    /// can update the activity while Kedro is suspended. nil (the default) keeps updates local.
    /// Installed by `.liveGameActivity()` from `PushService.liveActivityChannel(for:)`.
    @ObservationIgnored var channelProvider: (@MainActor (GameID) async -> String?)?

    /// Receives push-to-start tokens (hex) for `POST /v1/push/tokens {token, kind:"liveactivity"}`.
    /// Installed by `.liveGameActivity()` (`PushService.registerPushToStartToken`).
    @ObservationIgnored var onPushToStartToken: (@MainActor (String) async -> Void)?

    @ObservationIgnored private var activity: Activity<LiveGameAttributes>?
    @ObservationIgnored private var lastInput: Input?
    @ObservationIgnored private var lastSent: LiveGameAttributes.ContentState?
    @ObservationIgnored private var alertedRound: (game: GameID, round: Int)?
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "LiveActivity")

    /// Everything the content depends on.
    struct Input: Hashable, Sendable {
        var state: GameState
        var viewer: LiveActivityContent.Viewer
        var level: LanguageLevel
    }

    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // MARK: Following a game

    /// Follows a live game until the calling task is cancelled (the game closes or changes).
    func follow(_ session: GameSession, level: @escaping @MainActor () -> LanguageLevel) async {
        adoptExisting(for: session.gameID)
        await endActivities { $0.attributes.gameID != Self.key(session.gameID) }

        let heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
        defer { heartbeat.cancel() }

        let inputs = Observations { @MainActor in
            Input(state: session.state, viewer: LiveActivityContent.Viewer(session), level: level())
        }
        for await input in inputs {
            guard !Task.isCancelled else { break }
            await apply(input)
        }

        // The game was closed while still live (left the lobby, Done after the finish): nothing
        // to show any more.
        if let activity, activity.attributes.gameID == Self.key(session.gameID), activity.activityState == .active {
            await Self.end(activityID: activity.id, content: nil, policy: .immediate)
        }
        reset()
    }

    /// Ends leftover activities when Kedro launches without a live game.
    func endOrphansAfterGracePeriod() async {
        try? await Task.sleep(for: Self.orphanGracePeriod)
        guard !Task.isCancelled else { return }
        await endActivities { _ in true }
        reset()
    }

    /// Applies new game content: starts, updates or ends the activity.
    func apply(_ input: Input, now: Date = .now) async {
        lastInput = input
        let voice = Voice(level: input.level)
        guard let content = LiveActivityContent.contentState(for: input.state, viewer: input.viewer, voice: voice, now: now) else {
            return
        }

        switch content.phase {
        case .active:
            if let activity, activity.activityState == .active || activity.activityState == .stale {
                guard Self.differs(content, from: lastSent) else { return }
                await update(activity, with: content, alert: selfReportAlert(input, voice: voice), now: now)
            } else if activity == nil {
                await start(input, content: content, now: now)
            }
        case .finished:
            await end(with: content, policy: .after(now.addingTimeInterval(Self.finishedDismissalDelay)))
        case .abandoned:
            await end(with: content, policy: .immediate)
        }
    }

    /// Re-confirms the current content (heartbeat, returning to the foreground).
    func refresh(now: Date = .now) async {
        guard let lastInput, let activity, activity.activityState == .active || activity.activityState == .stale,
              let content = LiveActivityContent.contentState(
                  for: lastInput.state, viewer: lastInput.viewer, voice: Voice(level: lastInput.level), now: now
              ),
              content.phase == .active
        else { return }
        await update(activity, with: content, alert: nil, now: now)
    }

    // MARK: Buttons

    /// Routes `RecordRoundIntent` / `ReportHandIntent` taps here and picks up one that launched
    /// the app cold. Call once at launch.
    func installActionHandler() {
        LiveActivityActionInbox.handler = { [weak self] request in
            self?.receive(request)
        }
        if let waiting = LiveActivityActionInbox.take() {
            receive(waiting)
        }
    }

    func receive(_ request: LiveActivityActionRequest) {
        guard !request.isExpired() else { return }
        pendingAction = request
    }

    /// The button tapped for this game, if any. Clears it. The Table calls this when it appears
    /// (and when `pendingAction` changes) to open the Round sheet or Report Your Hand.
    func takePendingAction(for game: GameID, now: Date = .now) -> LiveActivityAction? {
        guard let request = pendingAction, request.gameID == Self.key(game) else { return nil }
        pendingAction = nil
        return request.isExpired(now: now) ? nil : request.action
    }

    /// Clears a request that can't be served (its game isn't the live one).
    func dropPendingAction() {
        pendingAction = nil
    }

    // MARK: Push

    /// Forwards push-to-start tokens to `onPushToStartToken` until cancelled.
    func observePushToStartTokens() async {
        for await data in Activity<LiveGameAttributes>.pushToStartTokenUpdates {
            let token = data.map { String(format: "%02x", $0) }.joined()
            await onPushToStartToken?(token)
        }
    }

    // MARK: Private

    private func start(_ input: Input, content: LiveGameAttributes.ContentState, now: Date) async {
        guard areActivitiesEnabled else { return }
        let attributes = LiveActivityContent.attributes(for: input.state, viewer: input.viewer)
        let channel = await channelProvider?(input.state.gameID)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: activityContent(content, now: now),
                pushType: channel.map { .channel($0) }
            )
            lastSent = content
            if input.viewer.seat.map({ LiveActivityContent.owesReport(input.state, me: $0) }) == true {
                alertedRound = (input.state.gameID, input.state.nextRoundNumber)
            }
        } catch {
            log.error("Couldn't start the Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func update(
        _ activity: Activity<LiveGameAttributes>,
        with content: LiveGameAttributes.ContentState,
        alert: AlertConfiguration?,
        now: Date
    ) async {
        await Self.update(activityID: activity.id, content: activityContent(content, now: now), alert: alert)
        lastSent = content
    }

    private func end(with content: LiveGameAttributes.ContentState, policy: ActivityUIDismissalPolicy) async {
        guard let activity else { return }
        await Self.end(activityID: activity.id, content: ActivityContent(state: content, staleDate: nil), policy: policy)
        self.activity = nil
        lastSent = content
    }

    private func activityContent(_ content: LiveGameAttributes.ContentState, now: Date) -> ActivityContent<LiveGameAttributes.ContentState> {
        ActivityContent(state: content, staleDate: now.addingTimeInterval(Self.staleInterval), relevanceScore: 100)
    }

    /// N-05 "Round 6: your hand. The table's waiting." once per round, only to a backgrounded
    /// phone that still owes a hand (design §13.2 "Self-report alert").
    private func selfReportAlert(_ input: Input, voice: Voice) -> AlertConfiguration? {
        let state = input.state
        guard !isAppActive, let me = input.viewer.seat, LiveActivityContent.owesReport(state, me: me) else { return nil }
        if let alertedRound, alertedRound.game == state.gameID, alertedRound.round == state.nextRoundNumber { return nil }
        alertedRound = (state.gameID, state.nextRoundNumber)
        let body = voice.line("N-05", ["r": state.nextRoundNumber])
        return AlertConfiguration(
            title: LocalizedStringResource(String.LocalizationValue(state.config.tableWord)),
            body: LocalizedStringResource(String.LocalizationValue(body)),
            sound: .default
        )
    }

    private func adoptExisting(for game: GameID) {
        guard activity == nil else { return }
        activity = Activity<LiveGameAttributes>.activities.first { $0.attributes.gameID == Self.key(game) }
    }

    private func endActivities(where shouldEnd: (Activity<LiveGameAttributes>) -> Bool) async {
        let ids = Activity<LiveGameAttributes>.activities.filter(shouldEnd).map(\.id)
        for id in ids {
            await Self.end(activityID: id, content: nil, policy: .immediate)
            if id == activity?.id { activity = nil }
        }
    }

    // `Activity` isn't Sendable, so its async calls run on an instance looked up in the same
    // (nonisolated) context rather than one sent from the main actor.

    nonisolated private static func update(
        activityID: String,
        content: ActivityContent<LiveGameAttributes.ContentState>,
        alert: AlertConfiguration?
    ) async {
        guard let activity = Activity<LiveGameAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        await activity.update(content, alertConfiguration: alert)
    }

    nonisolated private static func end(
        activityID: String,
        content: ActivityContent<LiveGameAttributes.ContentState>?,
        policy: ActivityUIDismissalPolicy
    ) async {
        guard let activity = Activity<LiveGameAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        await activity.end(content, dismissalPolicy: policy)
    }

    private func reset() {
        activity = nil
        lastInput = nil
        lastSent = nil
    }

    /// Content changed in a way worth an update (the timestamp alone isn't).
    static func differs(_ content: LiveGameAttributes.ContentState, from previous: LiveGameAttributes.ContentState?) -> Bool {
        guard var previous else { return true }
        previous.updatedAt = content.updatedAt
        return previous != content
    }

    /// The `gameID` string used in attributes and intents.
    static func key(_ game: GameID) -> String { game.uuidString.lowercased() }
}
