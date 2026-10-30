import Foundation
import OSLog

/// "Ask to Sit" for strangers (design §5.3, J-02). The operation log has no request type, so
/// asking travels outside it: the networking agent's `TableDiscovery` (or link) adopts this
/// protocol and the lobby picks it up with `app.discovery as? SeatRequesting`.
protocol SeatRequesting: AnyObject, Sendable {
    /// Asks the table's phones to seat this person. The host answers by seating them
    /// (a `PlayerSeated` op arrives) or not at all.
    func requestSeat(_ seat: Seat, at game: GameID) async throws

    /// Requests arriving at a table this phone hosts or sits at.
    func seatRequests(for game: GameID) -> AsyncStream<Seat>
}

/// Table links that the real transport checks (networking's `TableLink`): the rotating QR code
/// its admission accepts, and joining with a scanned code so the phone is let in without Ask to
/// Sit. `app.discovery as? TableInviting`; without it the lobby mints its own code.
protocol TableInviting: AnyObject {
    /// `https://kedro.app/t/{gameID}?k={code}` for the table this phone is linked to, or nil.
    func inviteLink(for game: GameID, at date: Date) -> URL?
    /// Starts linking with a table using the `k` from a scanned link.
    func prepareToJoin(_ game: GameID, inviteCode: String)
}

/// What the Table card does when you tap its button.
nonisolated enum SitDownAction: Hashable, Sendable {
    /// Played with the host, or the host added you: seats you now.
    case sitDown
    /// Never played together: the host decides (J-02).
    case askToSit
    /// Seats are set after Round 1 (J-04): read-only, queued for the rematch.
    case watch

    var title: String {
        switch self {
        case .sitDown: Literal.text("button.sitDown")
        case .askToSit: Literal.text("button.askToSit")
        case .watch: Literal.text("button.watch")
        }
    }

    static func action(isPlayedWith: Bool, hasSavedSeat: Bool, seatsLocked: Bool) -> SitDownAction {
        if hasSavedSeat { return .sitDown } // late phone matched to its seat (§5.7), even mid-game
        if seatsLocked { return .watch }
        return isPlayedWith ? .sitDown : .askToSit
    }
}

/// Gets this phone into a table found nearby, by link or by a saved seat (design §5.3, §5.5,
/// §5.7, §5.9): opens the game as the live game and sends a `PlayerSeated` for this person.
struct TableJoiner {
    enum JoinError: LocalizedError {
        case noProfile
        case tableFull
        case cantAsk

        var errorDescription: String? {
            switch self {
            case .noProfile: "Set up your profile first."
            case .tableFull: "That table's full. Watch this one; you're in the rematch."
            case .cantAsk: "Couldn't reach the table to ask. Scan the host's QR code instead."
            }
        }
    }

    let app: AppModel
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Join")

    /// How long to wait for the table's operations to arrive before seating.
    static let syncWait: Duration = .seconds(2)

    /// Performs the card's action. Returns the session (now the live game, presented).
    @discardableResult
    func perform(_ action: SitDownAction, at game: GameID, inviteCode: String? = nil) async throws -> GameSession {
        guard let profile = app.profile else { throw JoinError.noProfile }
        if let inviteCode, let inviting = app.discovery as? any TableInviting {
            // The scanned QR code admits this phone to the table's link (no Ask to Sit).
            inviting.prepareToJoin(game, inviteCode: inviteCode)
        }
        if action == .askToSit, !(app.discovery is any SeatRequesting) {
            log.info("Ask to Sit isn't available without a table link yet")
            throw JoinError.cantAsk
        }
        let session = try await app.makeSession(for: game)
        // Asking keeps the game running in the background so the host's answer (a PlayerSeated
        // for this person) is folded in; the card presents the Table when it arrives.
        app.startLiveGame(session, present: action != .askToSit)
        await waitForSync(session)

        switch action {
        case .watch:
            app.toasts.show(app.voice.line("J-04"))
        case .sitDown:
            let state = session.state
            if let existing = state.seat(for: profile.identity) {
                // A saved seat (or a phone joining late): link this phone to it.
                var seat = existing
                seat.deviceID = app.deviceID
                seat.languageLevel = app.preferences.effectiveLanguageLevel
                try await session.send(.playerSeated(.init(seat: seat)))
            } else {
                guard state.seats.count < GameConfig.seatRange.upperBound else { throw JoinError.tableFull }
                try await session.send(.playerSeated(.init(seat: mySeat(profile, order: state.seats.count))))
            }
        case .askToSit:
            guard let requests = app.discovery as? any SeatRequesting else { throw JoinError.cantAsk }
            try await requests.requestSeat(mySeat(profile, order: session.state.seats.count), at: game)
        }
        return session
    }

    private func mySeat(_ profile: LocalProfile, order: Int) -> Seat {
        profile.seat(order: order, device: app.deviceID, languageLevel: app.preferences.effectiveLanguageLevel, gamesPlayed: app.gamesPlayed(by: profile.identity))
    }

    /// Gives the transport a moment to bring in the table's log, so a saved seat is found and
    /// the new seat's order lands after the existing ones.
    private func waitForSync(_ session: GameSession) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.syncWait)
        while session.state.hostSeat == nil, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
