import Foundation
import Observation
import OSLog
import SwiftData

/// App-wide state and services, shared through the SwiftUI environment:
/// `@Environment(AppModel.self) private var app`.
///
/// Features reach every service through here (see apps/ios/ARCHITECTURE.md, "How features reach
/// services"). Replaceable services (`transport`, `directory`, `discovery`, `ageRange`) are
/// `var`s so the Networking and Lobby agents can install real implementations at launch in
/// `AppModel.live(container:)` without touching feature code.
@Observable
final class AppModel {
    // MARK: Navigation

    var selectedTab: AppTab = .play
    var playPath: [AppRoute] = []
    var boardPath: [AppRoute] = []
    var youPath: [AppRoute] = []
    var searchPath: [AppRoute] = []

    // MARK: Services

    let store: any GameStore
    var transport: any OperationTransport
    var directory: any PlayerDirectory
    var discovery: any TableDiscovery
    var ageRange: any AgeRangeProviding
    /// Profile upload and guest claims (networking's `AccountSync`). nil keeps the account on the
    /// phone (previews, tests).
    var account: (any AccountSyncing)?
    let toasts: ToastCenter
    let preferences: AppPreferences
    let profiles: ProfileStore
    let clock: HybridLogicalClock
    let deviceID: DeviceID
    let api: APIClient

    // MARK: Live game

    /// The game this phone is playing (or watching), if any. Shown as a `fullScreenCover` while
    /// `isTablePresented`, otherwise as the mini bar in the tab bar accessory.
    private(set) var liveGame: GameSession?
    var isTablePresented = false
    /// Run It Back from game end: the finished game to rebuild the lobby from. The Play tab opens
    /// the lobby with it (seats saved, rounds and mode pre-filled, first deal rotated) and clears it.
    var rematchRequest: GameState?
    @ObservationIgnored private var liveGameTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "App")

    init(
        store: any GameStore,
        transport: any OperationTransport = LocalOnlyTransport(),
        directory: (any PlayerDirectory)? = nil,
        discovery: any TableDiscovery = NoNearbyTables(),
        ageRange: any AgeRangeProviding = UndeclaredAgeRange(),
        preferences: AppPreferences = AppPreferences(),
        profiles: ProfileStore,
        deviceID: DeviceID = DeviceIdentity.current(),
        api: APIClient = APIClient(baseURL: AppConfig.apiBaseURL)
    ) {
        self.store = store
        self.transport = transport
        self.discovery = discovery
        self.ageRange = ageRange
        self.preferences = preferences
        self.profiles = profiles
        self.deviceID = deviceID
        self.api = api
        clock = HybridLogicalClock(device: deviceID)
        toasts = ToastCenter()
        self.directory = directory ?? LocalPlayerDirectory(store: store) { profiles.profile?.identity }
    }

    /// The app's real services. Falls back to in-memory storage (logged) if the on-disk store
    /// can't be opened, so the app still launches.
    static func live() -> AppModel {
        let container: ModelContainer?
        do {
            container = try KedroPersistence.makeContainer()
        } catch {
            Logger(subsystem: "com.njoy77.kedro", category: "App")
                .fault("Couldn't open the store, running in memory: \(error.localizedDescription, privacy: .public)")
            container = try? KedroPersistence.makeContainer(inMemory: true)
        }
        let store: any GameStore = container.map { SwiftDataGameStore(container: $0) } ?? InMemoryGameStore()
        // The real transport, directory, discovery and account sync need the AuthStore, so
        // `KedroApp` installs them right after this with `NetworkServices.install(in:auth:)`.
        // Until then (and in previews and tests) the local implementations run.
        return AppModel(store: store, profiles: ProfileStore(container: container))
    }

    // MARK: Identity

    var profile: LocalProfile? { profiles.profile }

    /// Who this phone is acting as.
    var identity: LocalIdentity {
        LocalIdentity(deviceID: deviceID, player: profile?.identity, displayName: profile?.displayName ?? "Someone")
    }

    /// Renders this player's personal surfaces (Play, You, notifications) in their level.
    var voice: Voice { Voice(level: preferences.effectiveLanguageLevel) }

    /// The house voice for a game's shared surfaces (Table, Round sheet, History, game end).
    func houseVoice(for state: GameState) -> Voice {
        Voice.house(for: state, viewer: preferences.effectiveLanguageLevel)
    }

    /// Call when auth reports a signed-in user: makes sure the local profile is that player, then
    /// uploads it and claims any guest history this phone holds (the server needs the player row
    /// before it accepts claims or ops).
    func didSignIn(userID: UUID, displayName: String?) {
        let player = PlayerRef.player(PlayerID(userID))
        var guestToken: String?
        if var existing = profile {
            if existing.identity != player {
                guestToken = existing.claimToken
                existing.identity = player
                existing.claimToken = nil
                profiles.save(existing)
            }
        } else {
            let name = displayName?.split(separator: " ").first.map(String.init) ?? "Player"
            profiles.save(LocalProfile(
                identity: player,
                displayName: name,
                handle: Handle.suggestions(firstName: name).first,
                avatar: .randomStarter()
            ))
        }
        guard let account else { return }
        Task {
            if preferences.hasCompletedOnboarding { _ = await syncProfile() }
            // The claimed games' seats change server side; the claimer gets no line (J-11 and
            // N-04 are for the other people at those tables, sent by the server).
            _ = await account.claimGuestHistory(guestToken: guestToken)
        }
    }

    /// Sends the profile to the server (end of onboarding, Settings → Profile, sign-in).
    func syncProfile() async -> ProfileUploadResult {
        guard let account, let profile else { return .notSent }
        return await account.uploadProfile(profile)
    }

    /// A local photo finished uploading: the profile (and every seat made from now on) uses its
    /// https URL, and the local copy goes. Ignored if the person picked another face meanwhile.
    func adoptUploadedPhoto(local: URL, uploaded: Avatar) {
        guard var profile, case .photo(let current) = profile.avatar, current == local else { return }
        profile.avatar = uploaded
        profiles.save(profile)
        if local.isFileURL { try? FileManager.default.removeItem(at: local) }
    }

    /// "Play as a guest": a local guest identity with a claim token (design §5.1).
    func playAsGuest(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profiles.save(LocalProfile(
            identity: .guest(GuestID()),
            displayName: trimmed.isEmpty ? "Guest" : trimmed,
            claimToken: UUID().uuidString
        ))
    }

    /// Whether to show onboarding instead of the tabs.
    func needsOnboarding(isSignedIn: Bool) -> Bool {
        !preferences.hasCompletedOnboarding || (!isSignedIn && profile?.isGuest != true)
    }

    // MARK: Launch

    /// Launch work: age range, resume an unfinished game. Call once from the root `.task`.
    func start() async {
        if let under18 = await ageRange.isUnder18() {
            preferences.isUnder18 = under18
        }
        await resumeLiveGame()
    }

    /// Reopens the newest lobby or active game this person is seated at (minimized).
    func resumeLiveGame() async {
        guard liveGame == nil, let me = profile?.identity else { return }
        do {
            for summary in try await store.liveGames() where summary.seats.contains(where: { $0.player == me }) {
                let session = try await makeSession(for: summary.id)
                startLiveGame(session, present: false)
                return
            }
        } catch {
            log.error("Couldn't resume a game: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Games

    /// A session for any stored game (live or read-only history). Not started: call `run()`.
    func makeSession(for game: GameID) async throws -> GameSession {
        let operations = try await store.operations(for: game)
        return GameSession(gameID: game, operations: operations, store: store, transport: transport, identity: identity, clock: clock)
    }

    /// Opens a new table with this phone's person as host (the lobby's first step).
    func createGame(config: GameConfig, others: [Seat] = []) async throws -> GameSession {
        guard let profile else { throw GameSession.SessionError.invalidRound }
        let host = profile.seat(order: 0, device: deviceID, languageLevel: preferences.effectiveLanguageLevel, gamesPlayed: gamesPlayed(by: profile.identity))
        let session = try await GameSession.create(
            config: config, host: host, others: others, store: store, transport: transport, identity: identity, clock: clock
        )
        preferences.lastPlannedRounds = config.plannedRounds
        preferences.lastScoringMode = config.scoringMode
        startLiveGame(session, present: false)
        return session
    }

    /// Makes a session the live game and keeps it folding in operations until it's closed.
    func startLiveGame(_ session: GameSession, present: Bool = true) {
        if liveGame?.gameID != session.gameID {
            liveGameTask?.cancel()
            liveGame = session
            liveGameTask = Task { await session.run() }
        }
        isTablePresented = present
    }

    /// Shows the Table full screen.
    func presentTable() {
        guard liveGame != nil else { return }
        isTablePresented = true
    }

    /// Minimizes the Table into the mini bar.
    func minimizeTable() {
        isTablePresented = false
    }

    /// Leaves the live game (after game end's Done, or leaving a lobby).
    func closeLiveGame() {
        isTablePresented = false
        liveGameTask?.cancel()
        liveGameTask = nil
        liveGame = nil
    }

    /// Finished games for a person, from Core/Stats, for the `Seat.gamesPlayed` snapshot (learner
    /// hints, the 5-step meter). nil until stats have loaded.
    func gamesPlayed(by person: PlayerRef) -> Int? {
        let stats = StatsModel.shared(for: store)
        return stats.isLoaded ? stats.progress(for: person).gamesPlayed : nil
    }

    // MARK: Navigation

    /// Pushes a route on a tab's stack (and switches to that tab).
    func navigate(to route: AppRoute, in tab: AppTab? = nil) {
        let tab = tab ?? selectedTab
        selectedTab = tab
        switch tab {
        case .play: playPath.append(route)
        case .board: boardPath.append(route)
        case .you: youPath.append(route)
        case .search: searchPath.append(route)
        }
    }
}

// MARK: - Previews

extension AppModel {
    /// An app model for previews: in-memory store with the demo history and the sample game
    /// (after Round 5, live), Noah's profile, and throwaway preferences.
    static func preview(liveGame: Bool = false, seeded: Bool = true) -> AppModel {
        var operations = seeded ? PreviewData.historyOperations : []
        operations += PreviewData.sampleOperations(throughRound: 5, finished: false)
        let defaults = UserDefaults(suiteName: "kedro.preview") ?? .standard
        let preferences = AppPreferences(defaults: defaults)
        preferences.hasCompletedOnboarding = true
        let model = AppModel(
            store: InMemoryGameStore(operations: operations),
            preferences: preferences,
            profiles: ProfileStore(container: nil, profile: PreviewData.noahProfile),
            deviceID: PreviewData.noahPhone
        )
        if liveGame {
            model.startLiveGame(PreviewData.sampleSession(throughRound: 5), present: false)
        }
        return model
    }
}
