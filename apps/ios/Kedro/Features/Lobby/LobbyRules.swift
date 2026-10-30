import Foundation

/// Something that stops the host from dealing.
nonisolated enum LobbyIssue: Hashable, Sendable {
    /// Under 3 seats (E-04).
    case tooFewSeats
    /// Over 8 seats (PRD §4.1).
    case tooManySeats
    /// The same person twice.
    case duplicateSeat(SeatID)
    /// Self-report mode: a guest with nobody to report for them.
    case reporterMissing(SeatID)
    /// A reporter who isn't seated, is a guest, or is the seat itself.
    case reporterInvalid(SeatID)
    case roundsOutOfRange
    /// The chosen first dealer isn't seated.
    case firstDealerNotSeated
    /// The chosen scorekeeper isn't seated.
    case scorekeeperNotSeated

    /// What to show under Deal. `tooFewSeats` is E-04 (a voice line); the rest are literal.
    func message(_ voice: Voice, seats: [Seat]) -> String {
        func name(_ id: SeatID) -> String { seats.first { $0.id == id }?.displayName ?? "Someone" }
        switch self {
        case .tooFewSeats: return voice.line("E-04")
        case .tooManySeats: return "A table holds \(GameConfig.seatRange.upperBound). Remove someone to deal."
        case .duplicateSeat(let id): return "\(name(id)) is seated twice."
        case .reporterMissing(let id): return "Pick someone to report for \(name(id))."
        case .reporterInvalid(let id): return "\(name(id)) needs a reporter with a phone at this table."
        case .roundsOutOfRange: return "Pick between \(GameConfig.plannedRoundsRange.lowerBound) and \(GameConfig.plannedRoundsRange.upperBound) rounds."
        case .firstDealerNotSeated: return "Pick who deals first."
        case .scorekeeperNotSeated: return "Pick a scorekeeper who's seated."
        }
    }
}

/// How a seat reads in the lobby (design §5.6, mockup frame 5). One line per seat.
nonisolated enum SeatRoleLine: Hashable, Sendable {
    /// "Host" or "Host · Scorekeeper".
    case host(isScorekeeper: Bool)
    case scorekeeper
    /// "Ben reports for Sam".
    case reportedBy(reporter: String, guest: String)
    /// A guest with no reporter (scorekeeper mode doesn't need one).
    case guest
    /// "Seat saved · waiting for their phone" (the table is open and nobody has sat in it).
    case waitingForPhone
    /// Unranked: the progress meter ("4 of 10").
    case meter(gamesPlayed: Int)
    /// "Played 21 together".
    case playedTogether(Int)
    /// Added from Search, never played together.
    case neverPlayed

    var text: String {
        switch self {
        case .host(let isScorekeeper): isScorekeeper ? "Host · Scorekeeper" : "Host"
        case .scorekeeper: "Scorekeeper"
        case let .reportedBy(reporter, guest): "\(reporter) reports for \(guest)"
        case .guest: "Guest"
        case .waitingForPhone: "Seat saved · waiting for their phone"
        case .meter(let games): Literal.text("label.meter", ["n": min(games, Ratings.rankedAfterGames), "total": Ratings.rankedAfterGames])
        case .playedTogether(let count): count == 1 ? "Played once together" : "Played \(count) together"
        case .neverPlayed: "Never played"
        }
    }
}

/// The lobby's rules, kept pure so they're testable (design §5.6, §5.9, PRD §4.1).
nonisolated enum LobbyRules {
    static var seatRange: ClosedRange<Int> { GameConfig.seatRange }

    /// Everything that blocks Deal, most important first. Empty means the host can deal.
    static func issues(seats: [Seat], config: GameConfig) -> [LobbyIssue] {
        var issues: [LobbyIssue] = []
        if seats.count < seatRange.lowerBound { issues.append(.tooFewSeats) }
        if seats.count > seatRange.upperBound { issues.append(.tooManySeats) }
        var seen = Set<SeatID>()
        for seat in seats where !seen.insert(seat.id).inserted {
            issues.append(.duplicateSeat(seat.id))
        }
        let ids = Set(seats.map(\.id))
        let reporters = Set(seats.filter { !$0.isGuest }.map(\.id))
        for seat in seats where seat.isGuest {
            if let reporter = seat.reporter {
                if !reporters.contains(reporter) || reporter == seat.id { issues.append(.reporterInvalid(seat.id)) }
            } else if config.scoringMode == .selfReport {
                issues.append(.reporterMissing(seat.id))
            }
        }
        if !GameConfig.plannedRoundsRange.contains(config.plannedRounds) { issues.append(.roundsOutOfRange) }
        if let dealer = config.firstDealerSeat, !ids.contains(dealer) { issues.append(.firstDealerNotSeated) }
        if config.scoringMode == .scorekeeper, let keeper = config.scorekeeperSeat, !ids.contains(keeper) {
            issues.append(.scorekeeperNotSeated)
        }
        return issues
    }

    static func canDeal(seats: [Seat], config: GameConfig) -> Bool {
        issues(seats: seats, config: config).isEmpty
    }

    /// Whether another person can be added.
    static func canAdd(to seats: [Seat]) -> Bool { seats.count < seatRange.upperBound }

    /// Whether a person is already seated.
    static func isSeated(_ person: PlayerRef, in seats: [Seat]) -> Bool {
        seats.contains { $0.player == person }
    }

    /// Adds a seat at the end (clockwise after the last), or nil if full or already seated.
    static func adding(_ seat: Seat, to seats: [Seat]) -> [Seat]? {
        guard canAdd(to: seats), !isSeated(seat.player, in: seats) else { return nil }
        var seat = seat
        seat.order = seats.count
        return seats + [seat]
    }

    /// Removes a seat, clearing any reporter assignments that pointed at it, and renumbers.
    static func removing(_ id: SeatID, from seats: [Seat]) -> [Seat] {
        renumbered(seats.filter { $0.id != id }.map { seat in
            var seat = seat
            if seat.reporter == id { seat.reporter = nil }
            return seat
        })
    }

    /// `onMove` for the clockwise seat list.
    static func moving(_ seats: [Seat], from source: IndexSet, to destination: Int) -> [Seat] {
        var moved = seats
        let items = source.sorted().map { moved[$0] }
        for index in source.sorted(by: >) { moved.remove(at: index) }
        let shift = source.filter { $0 < destination }.count
        moved.insert(contentsOf: items, at: max(0, min(moved.count, destination - shift)))
        return renumbered(moved)
    }

    /// Moves one seat a step clockwise (+1) or counter-clockwise (−1), for the ⋯ menu.
    static func moving(_ id: SeatID, by offset: Int, in seats: [Seat]) -> [Seat] {
        guard let index = seats.firstIndex(where: { $0.id == id }) else { return seats }
        let target = index + offset
        guard seats.indices.contains(target) else { return seats }
        var moved = seats
        moved.swapAt(index, target)
        return renumbered(moved)
    }

    /// Sets `order` to the array position (clockwise = dealing order).
    static func renumbered(_ seats: [Seat]) -> [Seat] {
        seats.enumerated().map { index, seat in
            var seat = seat
            seat.order = index
            return seat
        }
    }

    /// Self-report needs a reporter for every guest: default to the host (or the first seat with
    /// a phone) for any guest without one.
    static func withDefaultReporters(_ seats: [Seat], host: SeatID?) -> [Seat] {
        let fallback = host.flatMap { id in seats.first { $0.id == id && !$0.isGuest }?.id } ?? seats.first { !$0.isGuest }?.id
        return seats.map { seat in
            var seat = seat
            if seat.isGuest, seat.reporter == nil { seat.reporter = fallback }
            return seat
        }
    }

    /// Run It Back: the first dealer rotates one seat clockwise from last game's (design §5.7).
    static func rotatedFirstDealer(order: [SeatID], previous: SeatID?) -> SeatID? {
        guard let previous, let index = order.firstIndex(of: previous) else { return order.first }
        return order[(index + 1) % order.count]
    }

    /// The seat's one-line role (mockup frame 5).
    static func roleLine(
        for seat: Seat,
        in seats: [Seat],
        host: SeatID?,
        config: GameConfig,
        me: SeatID?,
        isOpen: Bool,
        playedTogether: Int?
    ) -> SeatRoleLine {
        let scorekeeper = config.scorekeeperSeat ?? host
        let keepsScore = config.scoringMode == .scorekeeper && scorekeeper == seat.id
        if seat.id == host { return .host(isScorekeeper: keepsScore) }
        if keepsScore { return .scorekeeper }
        if seat.isGuest {
            if let reporter = seat.reporter, let name = seats.first(where: { $0.id == reporter })?.displayName {
                return .reportedBy(reporter: name, guest: seat.displayName)
            }
            return .guest
        }
        if isOpen, seat.id != me, seat.deviceID == nil { return .waitingForPhone }
        if let games = seat.gamesPlayed, games < Ratings.rankedAfterGames { return .meter(gamesPlayed: games) }
        if let playedTogether, playedTogether > 0 { return .playedTogether(playedTogether) }
        return .neverPlayed
    }
}
