import Foundation
import Observation
import OSLog

/// The New Table lobby (design §5.6).
///
/// The lobby starts as a **draft** on this phone: seats and settings change freely. It **opens**
/// (sends `GameCreated` and a `PlayerSeated` per seat, and becomes the live game) when other
/// phones need to see it: on Invite with QR, when a real `TableDiscovery` is installed (so nearby
/// phones can Sit Down), and at the latest on Deal. Once open, every change is an operation:
/// add → `PlayerSeated`, remove → `SeatRemoved`, reorder and reporters → `PlayerSeated` upserts,
/// scorekeeper → `ScorekeeperChanged`, rounds → `RoundsChanged`, first deal → `GameStarted`.
///
/// The table word, scoring mode and house voice cap live in `GameCreated`'s config and have no
/// change operation. While no other phone has sat down, changing one quietly reopens the table
/// (the empty lobby is abandoned and a new one advertised); once someone else is linked to a seat
/// they lock (shared need: a lobby-only `GameConfigured` op would keep them editable throughout).
@Observable
final class LobbyModel {
    enum LobbyError: LocalizedError {
        case noProfile
        case cantDeal

        var errorDescription: String? {
            switch self {
            case .noProfile: "Set up your profile first."
            case .cantDeal: "Fix the seats first."
            }
        }
    }

    // MARK: State

    /// The open game, once other phones can see it.
    private(set) var session: GameSession?
    private var draftSeats: [Seat]
    private var draftConfig: GameConfig
    /// Who deals Round 1 (sent with `GameStarted`). nil means the host.
    var firstDealer: SeatID?
    /// Games played together, by player (the "Played 21 together" role line).
    private(set) var playedTogether: [PlayerID: Int] = [:]
    /// Lines for the Stakes section (J-xx).
    private(set) var stakes: [StakesLine] = []
    private(set) var isWorking = false
    /// The QR invite's rotating token (made when the table opens).
    private(set) var inviteToken: RotatingTableToken?
    /// The host's seat.
    let hostSeatID: SeatID

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var finished: [GameState] = []
    /// Seats this phone added, so arrivals from other phones can be announced (J-03).
    @ObservationIgnored private var knownSeats: Set<SeatID> = []
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "Lobby")

    // MARK: Init

    /// A fresh table, or a rematch (Run It Back: same people, rounds and mode; the first deal
    /// rotates one seat).
    init(app: AppModel, rematchOf previous: GameState? = nil) throws {
        guard let profile = app.profile else { throw LobbyError.noProfile }
        self.app = app
        let host = profile.seat(order: 0, device: app.deviceID, languageLevel: app.preferences.effectiveLanguageLevel, gamesPlayed: nil)
        hostSeatID = host.id
        var config = GameConfig(plannedRounds: app.preferences.lastPlannedRounds, scoringMode: app.preferences.lastScoringMode)
        var seats = [host]
        if let previous {
            config.plannedRounds = previous.config.plannedRounds
            config.scoringMode = previous.config.scoringMode
            for seat in previous.seats where seat.player != profile.identity {
                var seat = seat
                seat.deviceID = nil // a seat saved for them; their phone links it again
                seat.languageLevel = nil
                if let next = LobbyRules.adding(seat, to: seats) { seats = next }
            }
            let previousOrder = previous.seats.map(\.id)
            let rotated = LobbyRules.rotatedFirstDealer(order: previousOrder, previous: previous.config.firstDealerSeat)
            firstDealer = rotated.flatMap { id in seats.contains { $0.id == id } ? id : nil }
        }
        draftSeats = seats
        draftConfig = config
        knownSeats = Set(seats.map(\.id))
    }

    /// Reopens a lobby this phone already opened (the live game, still in the lobby).
    init(app: AppModel, session: GameSession) throws {
        guard let host = session.state.hostSeat else { throw LobbyError.noProfile }
        self.app = app
        self.session = session
        hostSeatID = host
        draftSeats = session.state.seats
        draftConfig = session.state.config
        firstDealer = session.state.config.firstDealerSeat
        knownSeats = Set(session.state.seats.map(\.id))
        inviteToken = TableTokenVault.token(for: session.gameID)
    }

    // MARK: Reading

    var isOpen: Bool { session != nil }

    /// Seats in clockwise order.
    var seats: [Seat] { session?.state.seats ?? draftSeats }

    var config: GameConfig {
        var config = session?.state.config ?? draftConfig
        config.firstDealerSeat = firstDealer
        return config
    }

    var gameID: GameID? { session?.gameID }

    /// Another phone is linked to a seat (someone sat down, or a saved seat was claimed).
    var otherPhonesSeated: Bool {
        seats.contains { $0.deviceID != nil && $0.deviceID != app.deviceID }
    }

    /// Table word, scoring mode and house voice can change until another phone sits down.
    var canChangeTableShape: Bool { !isOpen || !otherPhonesSeated }

    var issues: [LobbyIssue] { LobbyRules.issues(seats: seats, config: config) }

    var canDeal: Bool { issues.isEmpty && !isWorking }

    var canAdd: Bool { LobbyRules.canAdd(to: seats) }

    var hostName: String { seats.first { $0.id == hostSeatID }?.displayName ?? app.identity.displayName }

    /// The house voice tonight: the lowest level of anyone seated, capped by the host (§4.1).
    var houseLevel: LanguageLevel {
        LanguageLevel.house(seated: seats.compactMap(\.languageLevel), cap: config.houseVoiceCap)
    }

    /// J-15 shows when someone at the table lowered the voice below yours.
    var houseVoiceLowered: Bool { houseLevel < app.preferences.effectiveLanguageLevel }

    func roleLine(for seat: Seat) -> SeatRoleLine {
        LobbyRules.roleLine(
            for: seat, in: seats, host: hostSeatID, config: config, me: hostSeatID, isOpen: isOpen,
            playedTogether: seat.player.playerID.flatMap { playedTogether[$0] }
        )
    }

    func isSeated(_ person: PlayerRef) -> Bool { LobbyRules.isSeated(person, in: seats) }

    // MARK: Loading

    /// Played-with counts and stakes; opens the table right away when a real discovery is
    /// installed so nearby phones can Sit Down before Deal.
    func load() async {
        do {
            let playedWith = try await app.directory.playedWith()
            playedTogether = Dictionary(playedWith.map { ($0.player.id, $0.gamesTogether) }, uniquingKeysWith: max)
            finished = try await app.store.finishedGames()
        } catch {
            log.error("Couldn't load the lobby: \(error.localizedDescription, privacy: .public)")
        }
        refreshStakes()
        if !(app.discovery is NoNearbyTables), !isOpen {
            try? await open()
        }
    }

    private func refreshStakes() {
        guard let me = app.profile?.identity else { return }
        let others = Set(seats.map(\.player)).subtracting([me])
        stakes = PlayInsights.stakes(for: me, in: finished, opponents: others)
    }

    // MARK: Seats

    /// Seats a person (Played With, Search, Guest, or Let {name} In). Adding someone from
    /// Played With or Search is the host vouching: they're admitted without asking.
    func add(_ seat: Seat) async {
        guard let updated = LobbyRules.adding(withReporterIfNeeded(seat), to: seats) else { return }
        knownSeats.insert(seat.id)
        if let session, let added = updated.last {
            await send(.playerSeated(.init(seat: added)), in: session)
            // TODO(networking): "saved you a seat" push (N-01) for players added from Played With / Search.
        } else {
            draftSeats = updated
        }
        refreshStakes()
    }

    func add(_ player: PlayerSummary) async {
        await add(Seat(player, order: seats.count))
    }

    func remove(_ id: SeatID) async {
        guard id != hostSeatID else { return }
        if firstDealer == id { firstDealer = nil }
        if let session {
            // Clear reporters that pointed at this seat, then remove it.
            for seat in seats where seat.reporter == id {
                var cleared = seat
                cleared.reporter = nil
                await send(.playerSeated(.init(seat: cleared)), in: session)
            }
            await send(.seatRemoved(.init(seatId: id)), in: session)
        } else {
            draftSeats = LobbyRules.removing(id, from: draftSeats)
            if draftConfig.scorekeeperSeat == id { draftConfig.scorekeeperSeat = nil }
        }
        knownSeats.remove(id)
        refreshStakes()
    }

    func move(from source: IndexSet, to destination: Int) async {
        await reorder(LobbyRules.moving(seats, from: source, to: destination))
    }

    func move(_ id: SeatID, by offset: Int) async {
        await reorder(LobbyRules.moving(id, by: offset, in: seats))
    }

    private func reorder(_ reordered: [Seat]) async {
        if let session {
            let current = Dictionary(uniqueKeysWithValues: seats.map { ($0.id, $0.order) })
            for seat in reordered where current[seat.id] != seat.order {
                await send(.playerSeated(.init(seat: seat)), in: session)
            }
        } else {
            draftSeats = reordered
        }
    }

    func makeScorekeeper(_ id: SeatID) async {
        if let session {
            await send(.scorekeeperChanged(.init(seatId: id)), in: session)
        } else {
            draftConfig.scorekeeperSeat = id == hostSeatID ? nil : id
        }
    }

    /// Self-report: who reports for a guest without the app.
    func assignReporter(_ reporter: SeatID?, to guest: SeatID) async {
        guard var seat = seats.first(where: { $0.id == guest }) else { return }
        seat.reporter = reporter
        if let session {
            await send(.playerSeated(.init(seat: seat)), in: session)
        } else if let index = draftSeats.firstIndex(where: { $0.id == guest }) {
            draftSeats[index] = seat
        }
    }

    private func withReporterIfNeeded(_ seat: Seat) -> Seat {
        guard seat.isGuest, seat.reporter == nil, config.scoringMode == .selfReport else { return seat }
        var seat = seat
        seat.reporter = hostSeatID
        return seat
    }

    // MARK: Game settings

    var plannedRounds: Int { config.plannedRounds }

    func setPlannedRounds(_ rounds: Int) async {
        let rounds = min(max(rounds, GameConfig.plannedRoundsRange.lowerBound), GameConfig.plannedRoundsRange.upperBound)
        guard rounds != plannedRounds else { return }
        if let session {
            await send(.roundsChanged(.init(plannedRounds: rounds)), in: session)
        } else {
            draftConfig.plannedRounds = rounds
        }
    }

    func setScoringMode(_ mode: ScoringMode) async {
        guard mode != config.scoringMode else { return }
        await reshape { config, seats in
            config.scoringMode = mode
            if mode == .selfReport { seats = LobbyRules.withDefaultReporters(seats, host: self.hostSeatID) }
        }
    }

    func regenerateTableWord() async {
        await reshape { config, _ in config.tableWord = TableWord.random(excluding: config.tableWord) }
    }

    /// "Keep it cleaner tonight": the host can lower the house voice, never raise it.
    func capHouseVoice(at level: LanguageLevel?) async {
        guard level != config.houseVoiceCap else { return }
        await reshape { config, _ in config.houseVoiceCap = level }
    }

    /// Changes a setting carried by `GameCreated`. A draft just changes; an open table that only
    /// this phone has joined is reopened with the new settings (same seats).
    private func reshape(_ change: (inout GameConfig, inout [Seat]) -> Void) async {
        guard canChangeTableShape else { return }
        var config = self.config
        var seats = self.seats
        change(&config, &seats)
        guard let session else {
            draftConfig = config
            draftSeats = seats
            return
        }
        draftConfig = config
        draftSeats = LobbyRules.renumbered(seats)
        await close(session)
        do {
            try await open()
        } catch {
            log.error("Couldn't reopen the table: \(error.localizedDescription, privacy: .public)")
            app.toasts.show(app.voice.line("E-01"))
        }
    }

    // MARK: Opening, dealing, leaving

    /// Makes the table visible to other phones: `GameCreated` plus a seat each, as the live game
    /// (minimized; the lobby stays on screen). Idempotent.
    @discardableResult
    func open() async throws -> GameSession {
        if let session { return session }
        isWorking = true
        defer { isWorking = false }
        let others = draftSeats.filter { $0.id != hostSeatID }
        let session = try await app.createGame(config: draftConfig, others: others)
        self.session = session
        inviteToken = TableTokenVault.token(for: session.gameID)
        // `createGame` seats the host first; restore the draft's clockwise order.
        await reorder(LobbyRules.renumbered(draftSeats))
        await app.discovery.advertise(AdvertisedTable(
            gameID: session.gameID, hostName: hostName, tableWord: draftConfig.tableWord,
            seatCount: seats.count, roundsPlayed: 0
        ))
        return session
    }

    /// Deal: opens the table if needed, fixes the seats and first dealer, and flips every phone
    /// into the Table (other phones flip on `GameStarted`; this one when the lobby closes).
    func deal() async throws {
        guard canDeal else { throw LobbyError.cantDeal }
        let firstDealer = firstDealer
        let session = try await open()
        isWorking = true
        defer { isWorking = false }
        try await session.start(firstDealer: firstDealer ?? hostSeatID)
        app.preferences.lastPlannedRounds = session.state.config.plannedRounds
        app.preferences.lastScoringMode = session.state.config.scoringMode
        // The presenter shows the Table once the lobby sheet is gone (`app.presentTable()`).
        app.startLiveGame(session, present: false)
    }

    /// Cancel: a draft just goes away; an open lobby is abandoned (it never dealt, so it never
    /// counts) and stops advertising.
    func cancel() async {
        guard let session else { return }
        await close(session)
    }

    private func close(_ session: GameSession) async {
        defer { self.session = nil }
        guard session.state.status == .lobby else { return }
        do {
            try await session.abandon()
        } catch {
            log.error("Couldn't close the lobby: \(error.localizedDescription, privacy: .public)")
        }
        await app.discovery.stopAdvertising()
        if app.liveGame?.gameID == session.gameID { app.closeLiveGame() }
    }

    // MARK: Other phones

    /// New seats that arrived from other phones since the last call (J-03 toasts).
    func takeArrivals() -> [Seat] {
        let arrivals = seats.filter { !knownSeats.contains($0.id) && $0.deviceID != app.deviceID }
        knownSeats.formUnion(seats.map(\.id))
        if !arrivals.isEmpty { refreshStakes() }
        return arrivals
    }

    /// Ask to Sit requests from strangers (J-02), when the table link supports them.
    func seatRequests() -> AsyncStream<Seat>? {
        guard let gameID, let requests = app.discovery as? any SeatRequesting else { return nil }
        return requests.seatRequests(for: gameID)
    }

    private func send(_ payload: OperationPayload, in session: GameSession) async {
        do {
            try await session.send(payload)
        } catch {
            log.error("Lobby change failed: \(error.localizedDescription, privacy: .public)")
            app.toasts.show(app.voice.line("E-01"))
        }
    }
}
