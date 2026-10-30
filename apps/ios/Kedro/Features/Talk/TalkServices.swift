import Foundation
import Observation
import Supabase

/// The trash talk and sound services, shared app-wide (`TalkServices.shared`): the moderation
/// store, the sound player, the trash talk API, and the live monitors that turn incoming taunts
/// into toasts and game moments into sounds.
///
/// It lives here rather than in `AppModel` because `App/` belongs to foundation; views read
/// `TalkServices.shared`, tests build their own.
///
/// Wiring (see the talk agent's shared needs):
/// - `configure(auth:)` once at launch gives the API the signed-in user's token. The
///   `.trashTalk(for:)` modifier also does it on first use, so it works before that's wired.
/// - `.trashTalk(for:)` on the Table (and `presentsFeed: false` on the tab view for the minimized
///   game) keeps the monitor running.
@Observable
final class TalkServices {
    static let shared = TalkServices()

    let moderation: ModerationStore
    let sound: any SoundPlaying
    /// The `/v1` trash talk endpoints. Replaceable (tests, a shared networking client).
    var api: any TrashTalkAPI
    var filter: TauntFilter
    /// The game whose feed a tapped taunt toast asked to open (the Table presents it).
    var feedRequest: GameID?
    /// Games whose Table is in display mode right now: it shows taunts as full-width banners
    /// (design §6.3), so the monitor doesn't toast them as well.
    var bannerGames: Set<GameID> = []

    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var monitors: [GameID: MonitorHandle] = [:]

    private struct MonitorHandle {
        var task: Task<Void, Never>
        var holders: Int
    }

    init(
        moderation: ModerationStore = ModerationStore(),
        sound: any SoundPlaying = SoundPlayer(),
        api: any TrashTalkAPI = OfflineTrashTalkAPI(),
        filter: TauntFilter = .standard
    ) {
        self.moderation = moderation
        self.sound = sound
        self.api = api
        self.filter = filter
    }

    /// Points the API at the backend with the signed-in user's token. Safe to call repeatedly.
    func configure(auth: AuthStore) {
        guard !isConfigured else { return }
        isConfigured = true
        let client = auth.client
        api = TrashTalkHTTPClient(baseURL: AppConfig.apiBaseURL) {
            try? await client.auth.session.accessToken
        }
        Task { await moderation.flush(using: api) }
    }

    var moderator: TauntModerator { TauntModerator(filter: filter, api: api) }

    // MARK: Live monitor

    /// Keeps the toast and sound monitor running for a game while any caller is inside this
    /// call (the Table and the minimized mini bar both hold it, so it never runs twice).
    /// Returns when the calling task is cancelled.
    func hold(_ session: GameSession, app: AppModel) async {
        let id = session.gameID
        if var handle = monitors[id] {
            handle.holders += 1
            monitors[id] = handle
        } else {
            let monitor = LiveTalkMonitor(session: session, app: app, services: self)
            monitors[id] = MonitorHandle(task: Task { await monitor.run() }, holders: 1)
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3_600))
        }
        guard var handle = monitors[id] else { return }
        handle.holders -= 1
        if handle.holders <= 0 {
            handle.task.cancel()
            monitors[id] = nil
        } else {
            monitors[id] = handle
        }
    }

    /// Whether a monitor is running for a game (tests).
    func isMonitoring(_ game: GameID) -> Bool { monitors[game] != nil }

    // MARK: Safeguards

    /// Report: hides the taunt for this phone at once (T-13) and sends it for review.
    func report(_ taunt: TauntRecord, reason: ReportReason) {
        moderation.report(taunt, reason: reason)
        Task { await moderation.flush(using: api) }
    }

    func block(_ person: PlayerRef) {
        moderation.block(person)
        Task { await moderation.flush(using: api) }
    }

    func unblock(_ person: PlayerRef) {
        moderation.unblock(person)
        Task { await moderation.flush(using: api) }
    }

    /// Whether this phone shows a taunt (moderation, custom taunts setting, rate limits applied
    /// by `visibleTaunts`).
    func shows(_ taunt: TauntRecord, in game: GameID, preferences: AppPreferences) -> Bool {
        !moderation.hides(taunt, in: game, showsCustom: preferences.effectiveCustomTaunts)
    }

    /// The taunts this phone shows for a game, oldest first: within rate limits, not retracted,
    /// reported, muted or blocked, and custom ones only when custom taunts are on here.
    func visibleTaunts(in state: GameState, preferences: AppPreferences) -> [TauntRecord] {
        TauntRateLimit.withinLimits(state.taunts).filter { shows($0, in: state.gameID, preferences: preferences) }
    }
}
