import Foundation

/// Something the Add Player sheets can seat people at: the lobby before Deal (`LobbyModel`) or a
/// game in progress (`LateJoinModel`).
protocol SeatAdding: AnyObject {
    var seatCount: Int { get }
    /// Finished games with each player, for "Played 3 together".
    var playedTogether: [PlayerID: Int] { get }
    func isSeated(_ person: PlayerRef) -> Bool
    /// Whether this phone's person blocked someone (the sheets hide them).
    func hasBlocked(_ person: PlayerRef) -> Bool
    func add(_ seat: Seat) async
    func add(_ player: PlayerSummary) async
}

extension SeatAdding {
    /// Seats left at the table.
    var room: Int { max(0, GameConfig.seatRange.upperBound - seatCount) }

    /// Hidden from the sheets: already seated, or blocked.
    func isUnavailable(_ person: PlayerRef) -> Bool { isSeated(person) || hasBlocked(person) }
}

extension LobbyModel: SeatAdding {
    var seatCount: Int { seats.count }
}

/// Add Player once the game is underway (design §5.6, §6): a late joiner plays from the next
/// round at the highest total. The fold sets both, so this only sends the seat.
@Observable
final class LateJoinModel: SeatAdding {
    let session: GameSession
    private(set) var playedTogether: [PlayerID: Int] = [:]

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let claimCodes: any GuestClaimCodeStoring
    @ObservationIgnored private let isBlocked: (PlayerRef) -> Bool

    init(
        app: AppModel,
        session: GameSession,
        claimCodes: any GuestClaimCodeStoring = KeychainGuestClaimCodes.shared,
        isBlocked: @escaping (PlayerRef) -> Bool = { TalkServices.shared.moderation.isBlocked($0) }
    ) {
        self.app = app
        self.session = session
        self.claimCodes = claimCodes
        self.isBlocked = isBlocked
    }

    var seatCount: Int { session.state.seats.count }

    func isSeated(_ person: PlayerRef) -> Bool { session.state.seat(for: person) != nil }

    func hasBlocked(_ person: PlayerRef) -> Bool { isBlocked(person) }

    func load() async {
        let playedWith = (try? await app.directory.playedWith()) ?? []
        playedTogether = Dictionary(playedWith.map { ($0.player.id, $0.gamesTogether) }, uniquingKeysWith: max)
    }

    func add(_ player: PlayerSummary) async {
        await add(Seat(player, order: seatCount))
    }

    func add(_ seat: Seat) async {
        guard session.canEdit, room > 0, !isUnavailable(seat.player) else { return }
        var seat = LobbyModel.withClaimCode(seat, codes: claimCodes)
        if seat.gamesPlayed == nil { seat.gamesPlayed = app.gamesPlayed(by: seat.player) }
        if seat.isGuest, seat.reporter == nil, session.state.config.scoringMode == .selfReport {
            seat.reporter = session.mySeatID
        }
        do {
            try await session.send(.playerSeated(.init(seat: seat)))
            if let joined = session.state.seat(seat.id), let round = joined.joinedRound {
                let line = app.houseVoice(for: session.state).line("G-10", [
                    "name": joined.displayName, "r": round, "score": ScoreFormat.string(joined.startingScore ?? 0),
                ])
                app.toasts.show(line)
            }
        } catch {
            app.toasts.show(error.localizedDescription)
        }
    }
}
