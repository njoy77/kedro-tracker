import Foundation
import Observation
import OSLog

/// The App Clip's state (design §5.8): a guest with an iPhone and no app scans the table's QR
/// (or gets it by AirDrop), says which guest seat is theirs, then watches the live Table, reports
/// their own hand in self-report games, and sends canned taunts. At the end they see their result
/// and "Get Kedro to keep this"; the claim token waits in the app group for the full app.
///
/// The clip uses the internet only (no peer-to-peer link): `ClipTransport` polls the backend.
@Observable
final class ClipModel {
    enum Phase: Equatable {
        /// Launched without an invite link (from the App Clips library, or a bad link).
        case waitingForInvite
        case connecting
        /// Couldn't reach the backend (F-04).
        case offline
        /// The link's token expired or the game doesn't exist.
        case expired
        /// The game is live: pick a seat, then play.
        case table
    }

    private(set) var phase: Phase = .waitingForInvite
    /// The game being shown (watching until a seat is picked).
    private(set) var session: GameSession?
    /// The seat this phone said is theirs.
    private(set) var mySeat: SeatID?
    /// Chose Watch instead of a seat (not on the list, or seats are fixed after Round 1).
    var isWatching = false
    /// A seat pick or report in flight.
    private(set) var isWorking = false
    /// The last error worth telling the guest about (literal).
    var errorMessage: String?

    let deviceID: DeviceID
    /// The clip has no settings and no age check, so its own voice is Clean; canned taunts it
    /// sends still render in each recipient's level.
    let voice = Voice(level: .clean)

    @ObservationIgnored private let api: ClipAPI?
    @ObservationIgnored private let claims: ClaimTokenStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var invite: (gameID: GameID, token: String?)?
    @ObservationIgnored private var transport: ClipTransport?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro.clip", category: "Clip")

    init(
        api: ClipAPI? = ClipAPI.fromBundle(),
        claims: ClaimTokenStore = ClaimTokenStore(),
        defaults: UserDefaults = .standard,
        deviceID: DeviceID = DeviceIdentity.current()
    ) {
        self.api = api
        self.claims = claims
        self.defaults = defaults
        self.deviceID = deviceID
    }

    // MARK: Derived

    var state: GameState? { session?.state }

    /// "Noah" (falls back to the first seat's name before the host is known).
    var hostName: String {
        guard let state else { return "the host" }
        if let host = state.hostSeat { return state.name(of: host) }
        return state.seats.first?.displayName ?? "the host"
    }

    /// Guest seats nobody's phone has claimed yet, plus the one this phone already holds.
    var openGuestSeats: [Seat] {
        guard let state else { return [] }
        return state.seats.filter { $0.isGuest && ($0.deviceID == nil || $0.deviceID == deviceID) }
    }

    var isOffline: Bool {
        phase == .offline || transport?.syncState == .offlineSolo
    }

    /// Self-report games: this guest still owes their hand for the round being played.
    var owesHand: Bool {
        guard let state, let mySeat, state.status == .active, state.config.scoringMode == .selfReport,
              !state.isAwaitingFinish
        else { return false }
        return state.selfReport?.hands[mySeat] == nil
    }

    // MARK: Invocation

    /// Handles the invocation URL (`https://playkedro.com/t/{gameID}?k={token}`).
    func open(_ url: URL?) {
        guard let url, case .invite(let gameID, let token) = KedroLink(url: url) else {
            if session == nil { phase = .waitingForInvite }
            return
        }
        let game = GameID(gameID)
        guard invite?.gameID != game || phase != .table else { return }
        invite = (game, token)
        Task { await connect() }
    }

    /// Joins the invite's game (again, after going offline).
    func connect() async {
        guard let invite else {
            phase = .waitingForInvite
            return
        }
        guard let api, let token = invite.token else {
            phase = api == nil ? .offline : .expired
            return
        }
        phase = .connecting
        do {
            let access = try await api.startSession(gameID: invite.gameID, tableToken: token, deviceID: deviceID)
            let operations = try await api.operations(gameID: invite.gameID, after: nil, token: access.accessToken)
            guard !operations.isEmpty else {
                phase = .expired
                return
            }
            let transport = ClipTransport(api: api, accessToken: access.accessToken, latest: operations.map(\.hlc).max())
            self.transport = transport
            accessToken = access.accessToken
            mySeat = rememberedSeat(for: invite.gameID)
            startSession(gameID: invite.gameID, operations: operations)
            phase = .table
        } catch ClipAPI.ClipAPIError.badStatus(let status) where (400..<500).contains(status) {
            phase = .expired
        } catch {
            log.error("Clip couldn't connect: \(error.localizedDescription, privacy: .public)")
            phase = .offline
        }
    }

    // MARK: Actions

    /// "That's me": links this phone to a guest seat, then fetches a claim token for the app.
    func claim(_ seat: Seat) async {
        guard let session, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        var linked = seat
        linked.deviceID = deviceID
        linked.languageLevel = .clean
        do {
            if seat.deviceID != deviceID {
                try await session.send(.playerSeated(.init(seat: linked)))
            }
            mySeat = seat.id
            remember(seat.id, for: session.gameID)
            startSession(gameID: session.gameID, operations: session.operations)
            await fetchClaimToken(for: seat, gameID: session.gameID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Self-report: this guest's hand for the round being played.
    func reportHand(_ hand: Int, knocked: Bool) async {
        guard let session, let mySeat, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await session.reportHand(hand, knocked: knocked, for: mySeat)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A canned taunt (custom taunts need the full app's filter and report flow).
    func sendTaunt(_ id: String, to target: TauntTarget) async {
        guard let session else { return }
        do {
            try await session.sendTaunt(.canned(id: id), to: target)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Private

    private func startSession(gameID: GameID, operations: [GameOperation]) {
        guard let transport else { return }
        runTask?.cancel()
        let seat = mySeat.flatMap { id in GameState.fold(operations, gameID: gameID).seat(id) }
        let identity = LocalIdentity(deviceID: deviceID, player: seat?.player, displayName: seat?.displayName ?? "Guest")
        let session = GameSession(
            gameID: gameID,
            operations: operations,
            store: InMemoryGameStore(operations: operations),
            transport: transport,
            identity: identity,
            clock: HybridLogicalClock(device: deviceID)
        )
        self.session = session
        runTask = Task { await session.run() }
        if let seat {
            recordClaim(for: seat, gameID: gameID, token: nil)
        }
    }

    private func fetchClaimToken(for seat: Seat, gameID: GameID) async {
        guard let api, let accessToken else { return }
        do {
            let token = try await api.claimSeat(gameID: gameID, seatID: seat.id, token: accessToken)
            recordClaim(for: seat, gameID: gameID, token: token)
        } catch {
            // The game is still recorded; the next launch (or the app's sign-in) retries.
            log.error("Clip couldn't get a claim token: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recordClaim(for seat: Seat, gameID: GameID, token: String?) {
        guard case .guest(let guestID) = seat.player else { return }
        claims.record(
            guestID: guestID.uuidString.lowercased(),
            displayName: seat.displayName,
            gameID: gameID.uuidString.lowercased(),
            hostName: hostName,
            claimToken: token
        )
    }

    private static func seatKey(_ game: GameID) -> String { "clip.seat.\(game.uuidString.lowercased())" }

    private func rememberedSeat(for game: GameID) -> SeatID? {
        defaults.string(forKey: Self.seatKey(game)).flatMap(SeatID.init(rawValue:))
    }

    private func remember(_ seat: SeatID, for game: GameID) {
        defaults.set(seat.rawValue, forKey: Self.seatKey(game))
    }
}

// MARK: - Previews

extension ClipModel {
    /// The sample game after Round 1 with Sam's guest seat open, as the clip would see it.
    static func preview(seated: Bool = false, throughRound round: Int = 1, finished: Bool = false) -> ClipModel {
        let model = ClipModel(api: nil, defaults: UserDefaults(suiteName: "kedro.clip.preview") ?? .standard, deviceID: DeviceID())
        let operations = PreviewData.sampleOperations(throughRound: round, finished: finished)
        model.transport = nil
        model.mySeat = seated ? PreviewData.samSeat : nil
        let seat = model.mySeat.flatMap { GameState.fold(operations, gameID: PreviewData.sampleGameID).seat($0) }
        model.session = GameSession(
            gameID: PreviewData.sampleGameID,
            operations: operations,
            store: InMemoryGameStore(operations: operations),
            transport: LocalOnlyTransport(),
            identity: LocalIdentity(deviceID: model.deviceID, player: seat?.player, displayName: seat?.displayName ?? "Guest"),
            clock: HybridLogicalClock(device: model.deviceID)
        )
        model.phase = .table
        return model
    }
}
