import Foundation
import Observation
import OSLog

/// The Play tab's state (design §12.1): nearby tables and the Table card, saved seats, the
/// digest, stakes and recent games. Everything is derived from `app.store` and `app.discovery`.
@Observable
final class PlayModel {
    // MARK: Tables

    /// Visible tables, closest first.
    private(set) var nearby: [NearbyTable] = []
    /// Tables whose card was dismissed: they move to a Nearby row (§5.3).
    private(set) var dismissed: Set<GameID> = []
    /// Lobby games on this phone where the host saved you a seat and you haven't sat down (§5.5).
    private(set) var savedSeats: [GameState] = []
    /// A table opened from a link (QR, AirDrop, the saved-seat push) or Join with Code.
    var linkedTable: TableCardContent?
    /// The card's table after Ask to Sit, until the host answers.
    var askedTable: GameID?
    var isJoining = false

    // MARK: Between games

    private(set) var recent: [GameSummary] = []
    private(set) var digest: [DigestItem] = []
    private(set) var stakes: [StakesLine] = [.nothing]
    private(set) var myGamesPlayed = 0
    private(set) var finished: [GameState] = []
    /// The Wrapped slot from Core/Stats (December, or last year's until the next one).
    private(set) var wrapped: WrappedSlot?

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "Play")
    /// `lastLookedAt` as it was when Play opened, so the digest doesn't empty while you read it.
    @ObservationIgnored private var digestSince: Date?
    @ObservationIgnored private var digestSinceCaptured = false

    init(app: AppModel) {
        self.app = app
    }

    // MARK: The Table card

    /// The card on top of Play: a link first, then a saved seat, then the closest table.
    var card: TableCardContent? {
        // Already at a table: no card (the mini bar covers it), unless it's the one you asked to join.
        if let live = app.liveGame, askedTable != live.gameID { return nil }
        if let linkedTable, !dismissed.contains(linkedTable.id) { return linkedTable }
        let me = app.profile?.identity
        if let saved = savedSeats.first(where: { !dismissed.contains($0.gameID) }) {
            if let table = nearby.first(where: { $0.id == saved.gameID }) {
                return TableCardContent(table: table, hasSavedSeat: true)
            }
            return TableCardContent(gameID: saved.gameID, state: saved, link: nil, me: me)
        }
        return nearby.first { !dismissed.contains($0.id) }.map { table in
            TableCardContent(table: table, hasSavedSeat: savedSeats.contains { $0.gameID == table.id })
        }
    }

    /// Tables other than the card's (the J-16 link and the Nearby rows).
    var otherTables: [NearbyTable] {
        nearby.filter { $0.id != card?.id }
    }

    /// Dismissed tables still visible: shown as Nearby rows on Play.
    var nearbyRows: [NearbyTable] {
        guard app.liveGame == nil else { return [] }
        return nearby.filter { dismissed.contains($0.id) }
    }

    func dismissCard() {
        guard let card else { return }
        dismissed.insert(card.id)
        if linkedTable?.id == card.id { linkedTable = nil }
    }

    /// Brings a table back as the card (Nearby row, the other-tables list, Join with Code).
    func showCard(for table: NearbyTable) {
        dismissed.remove(table.id)
        linkedTable = TableCardContent(table: table, hasSavedSeat: savedSeats.contains { $0.gameID == table.id })
    }

    /// Opens a table link (QR, AirDrop, saved-seat push). Returns false for links that aren't ours.
    @discardableResult
    func open(_ url: URL) async -> Bool {
        guard let link = TableInviteLink(url: url) else { return false }
        // The table's link checks the code (`k`) when this phone sits down (TableJoiner).
        let state = try? await app.store.gameState(link.gameID)
        if let table = nearby.first(where: { $0.id == link.gameID }) {
            var content = TableCardContent(table: table, hasSavedSeat: link.kind == .savedSeat)
            content.isPlayedWith = true // the host handed you the link
            content.inviteCode = link.token
            linkedTable = content
        } else {
            linkedTable = TableCardContent(gameID: link.gameID, state: state, link: link, me: app.profile?.identity)
        }
        dismissed.remove(link.gameID)
        return true
    }

    /// Join with Code: finds a nearby table by its table word ("cold deck").
    func table(matching word: String) -> NearbyTable? {
        let typed = TableWord.normalized(word)
        return nearby.first { TableWord.normalized($0.tableWord) == typed }
    }

    /// Sit Down / Ask to Sit / Watch on the card.
    func performCardAction() async {
        guard let card else { return }
        isJoining = true
        defer { isJoining = false }
        do {
            let action = card.action
            switch try await TableJoiner(app: app).perform(action, at: card.id, inviteCode: card.inviteCode) {
            case .confirmGuestSeat(let session, let seat):
                guestSeatConfirmation = GuestSeatConfirmation(session: session, seat: seat, fallback: action)
            case .done:
                if action == .askToSit {
                    askedTable = card.id
                } else {
                    linkedTable = nil
                }
            }
        } catch {
            app.toasts.show(error.localizedDescription)
        }
    }

    /// "Is this Sam?" for a guest seat the host typed in with this phone's name.
    var guestSeatConfirmation: GuestSeatConfirmation?

    struct GuestSeatConfirmation: Identifiable {
        let session: GameSession
        let seat: Seat
        /// What the card would have done otherwise ("Not me").
        let fallback: SitDownAction
        var id: SeatID { seat.id }
    }

    /// "Yes, that's me": takes over the guest seat.
    func confirmGuestSeat() async {
        guard let confirmation = guestSeatConfirmation else { return }
        guestSeatConfirmation = nil
        do {
            try await TableJoiner(app: app).takeOver(confirmation.seat, in: confirmation.session)
            linkedTable = nil
        } catch {
            app.toasts.show(error.localizedDescription)
        }
    }

    /// Not them: the card's own action after all (a seat of their own, Ask to Sit, or Watch).
    func declineGuestSeat() async {
        guard let confirmation = guestSeatConfirmation, let card else { return }
        guestSeatConfirmation = nil
        guard let profile = app.profile else { return }
        do {
            let session = confirmation.session
            switch confirmation.fallback {
            case .watch:
                app.toasts.show(app.voice.line("J-04"))
            case .sitDown:
                guard session.state.seats.count < GameConfig.seatRange.upperBound else { throw TableJoiner.JoinError.tableFull }
                let seat = profile.seat(order: session.state.seats.count, device: app.deviceID, languageLevel: app.preferences.effectiveLanguageLevel, gamesPlayed: app.gamesPlayed(by: profile.identity))
                try await session.send(.playerSeated(.init(seat: seat)))
            case .askToSit:
                guard let requests = app.discovery as? any SeatRequesting else { throw TableJoiner.JoinError.cantAsk }
                let seat = profile.seat(order: session.state.seats.count, device: app.deviceID, languageLevel: app.preferences.effectiveLanguageLevel, gamesPlayed: app.gamesPlayed(by: profile.identity))
                try await requests.requestSeat(seat, at: card.id)
                askedTable = card.id
                return
            }
            linkedTable = nil
        } catch {
            app.toasts.show(error.localizedDescription)
        }
    }

    /// The host answered Ask to Sit by seating you: open the Table.
    func checkAskAnswered() {
        guard let asked = askedTable, let live = app.liveGame, live.gameID == asked, live.mySeat != nil else { return }
        askedTable = nil
        linkedTable = nil
        app.presentTable()
    }

    // MARK: Loading

    /// Follows nearby tables until cancelled.
    func followNearbyTables() async {
        for await tables in app.discovery.nearbyTables() {
            nearby = tables
        }
    }

    /// Reloads everything derived from the store; then again whenever a game changes.
    func followStore() async {
        await reload()
        for await _ in app.store.gameUpdates() {
            await reload()
        }
    }

    func reload() async {
        if !digestSinceCaptured {
            digestSince = app.preferences.lastLookedAt
            digestSinceCaptured = true
        }
        do {
            let games = try await app.store.games()
            recent = games.filter { game in
                // A lobby that never dealt (cancelled) isn't a game.
                !(game.status == .abandoned && game.roundsPlayed == 0) && game.status != .lobby
            }
            finished = try await app.store.countedGames()
            try await loadSavedSeats(from: games)
        } catch {
            log.error("Couldn't load Play: \(error.localizedDescription, privacy: .public)")
        }
        guard let me = app.profile?.identity else {
            digest = []
            stakes = [.nothing]
            myGamesPlayed = 0
            return
        }
        refreshInsights()
        checkAskAnswered()
    }

    /// Recomputes the digest and stakes: from Core/Stats once it has loaded (ratings, board
    /// movement, badges), from finished games before that.
    func refreshInsights() {
        guard let me = app.profile?.identity else { return }
        let stats = StatsModel.shared(for: app.store)
        let voice = app.voice
        myGamesPlayed = stats.isLoaded ? stats.progress(for: me).gamesPlayed : PlayInsights.gamesPlayed(by: me, in: finished)
        stakes = PlayInsights.stakes(provider: stats, isLoaded: stats.isLoaded, me: me, table: [], voice: voice)
            ?? PlayInsights.stakes(for: me, in: finished, limit: 1)
        // A line already in Tonight's stakes (the closest badge, usually) isn't repeated above it.
        let stakesText = Set(stakes.map { $0.text(voice) })
        digest = (PlayInsights.digest(provider: stats, isLoaded: stats.isLoaded, me: me, in: finished, since: digestSince, voice: voice)
            ?? PlayInsights.digest(for: me, in: finished, since: digestSince))
            .filter { item in
                if case .stats(let line) = item { return !stakesText.contains(line.text) }
                return true
            }
        wrapped = stats.isLoaded ? stats.wrappedSlot(for: me, voice: voice, now: .now) : nil
    }

    /// Stakes for the people at a table (the card).
    func stakes(at card: TableCardContent) -> [StakesLine] {
        guard let me = app.profile?.identity else { return [] }
        let opponents = card.seated.map(\.ref)
        let stats = StatsModel.shared(for: app.store)
        return PlayInsights.stakes(provider: stats, isLoaded: stats.isLoaded, me: me, table: opponents, voice: app.voice)
            ?? PlayInsights.stakes(for: me, in: finished, opponents: Set(opponents))
    }

    /// Marks the digest as seen (when you leave Play).
    func markLooked() {
        app.preferences.lastLookedAt = .now
    }

    private func loadSavedSeats(from games: [GameSummary]) async throws {
        guard let me = app.profile?.identity else {
            savedSeats = []
            return
        }
        var saved: [GameState] = []
        for summary in games where summary.status.isLive {
            guard let seat = summary.seats.first(where: { $0.player == me }), seat.deviceID == nil,
                  let state = try await app.store.gameState(summary.id), state.hostSeat != seat.id
            else { continue }
            saved.append(state)
        }
        savedSeats = saved
    }
}
