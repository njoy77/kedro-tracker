import Foundation
import Testing
@testable import Kedro

@Suite("Lobby rules")
struct LobbyRulesTests {
    private func players(_ count: Int) -> [Seat] {
        LobbyRules.renumbered((0..<count).map { index in
            Seat(player: .player(PlayerID()), displayName: "P\(index)", order: index, handle: Handle(constant: "player\(index)"))
        })
    }

    private func guest(_ name: String, reporter: SeatID? = nil) -> Seat {
        Seat(player: .guest(GuestID()), displayName: name, order: 0, reporter: reporter)
    }

    // MARK: Deal

    @Test("Deal needs 3 to 8 seats", arguments: 0...10)
    func seatCount(count: Int) {
        let issues = LobbyRules.issues(seats: players(count), config: GameConfig())
        #expect(issues.contains(.tooFewSeats) == (count < 3))
        #expect(issues.contains(.tooManySeats) == (count > 8))
        #expect(LobbyRules.canDeal(seats: players(count), config: GameConfig()) == (3...8).contains(count))
    }

    @Test("Under 3 seats shows E-04 in every level")
    func underThreeMessage() {
        for level in LanguageLevel.allCases {
            let voice = Voice(level: level)
            #expect(LobbyIssue.tooFewSeats.message(voice, seats: []) == "Cambio needs 3. Two people is just a staring contest.")
        }
    }

    @Test("The same person can't be seated twice")
    func duplicates() {
        var seats = players(3)
        seats.append(seats[0])
        #expect(LobbyRules.issues(seats: seats, config: GameConfig()).contains(.duplicateSeat(seats[0].id)))
        #expect(LobbyRules.adding(seats[1], to: players(3)) != nil)
        let three = players(3)
        #expect(LobbyRules.adding(three[1], to: three) == nil)
    }

    @Test("Self-report needs a phone-holding reporter for every guest")
    func reporters() {
        let seats = players(3)
        let sam = guest("Sam")
        var config = GameConfig(scoringMode: .selfReport)
        #expect(LobbyRules.issues(seats: seats + [sam], config: config) == [.reporterMissing(sam.id)])

        // Scorekeeper mode doesn't need one.
        config.scoringMode = .scorekeeper
        #expect(LobbyRules.issues(seats: seats + [sam], config: config).isEmpty)

        // A guest can't report for a guest, and nobody reports for themselves.
        config.scoringMode = .selfReport
        let leo = guest("Leo")
        let samForLeo = guest("Sam", reporter: leo.id)
        #expect(LobbyRules.issues(seats: seats + [leo, samForLeo], config: config).contains(.reporterInvalid(samForLeo.id)))
        let fixed = LobbyRules.withDefaultReporters(seats + [sam], host: seats[0].id)
        #expect(fixed.last?.reporter == seats[0].id)
        #expect(LobbyRules.issues(seats: fixed, config: config).isEmpty)
    }

    @Test("Default reporters fall back to the first seat with a phone")
    func defaultReporterFallback() {
        let sam = guest("Sam")
        let seats = [guest("Leo")] + players(2) + [sam]
        let fixed = LobbyRules.withDefaultReporters(seats, host: nil)
        #expect(fixed.filter(\.isGuest).allSatisfy { $0.reporter == seats[1].id })
    }

    @Test("Rounds, first dealer and scorekeeper must make sense")
    func settings() {
        let seats = players(3)
        let stranger = PlayerRef.player(PlayerID()).seatID
        #expect(LobbyRules.issues(seats: seats, config: GameConfig(plannedRounds: 0)) == [.roundsOutOfRange])
        #expect(LobbyRules.issues(seats: seats, config: GameConfig(plannedRounds: 51)) == [.roundsOutOfRange])
        #expect(LobbyRules.issues(seats: seats, config: GameConfig(firstDealerSeat: stranger)) == [.firstDealerNotSeated])
        #expect(LobbyRules.issues(seats: seats, config: GameConfig(scorekeeperSeat: stranger)) == [.scorekeeperNotSeated])
        #expect(LobbyRules.issues(seats: seats, config: GameConfig(scoringMode: .selfReport, scorekeeperSeat: stranger)).isEmpty)
    }

    // MARK: Seats

    @Test("A full table refuses a ninth seat")
    func full() {
        let eight = players(8)
        #expect(!LobbyRules.canAdd(to: eight))
        #expect(LobbyRules.adding(players(1)[0], to: eight) == nil)
        let added = LobbyRules.adding(guest("Sam"), to: players(7))
        #expect(added?.count == 8)
        #expect(added?.last?.order == 7)
    }

    @Test("Removing a seat renumbers and clears reporters that pointed at it")
    func removing() {
        let seats = players(3)
        let sam = guest("Sam", reporter: seats[1].id)
        let remaining = LobbyRules.removing(seats[1].id, from: LobbyRules.renumbered(seats + [sam]))
        #expect(remaining.map(\.order) == [0, 1, 2])
        #expect(remaining.last?.reporter == nil)
        #expect(!remaining.contains { $0.id == seats[1].id })
    }

    @Test("Moving follows List.onMove semantics and keeps orders clockwise")
    func moving() {
        let seats = players(5)
        let ids = seats.map(\.id)
        // Drag the first seat to the end.
        let moved = LobbyRules.moving(seats, from: IndexSet(integer: 0), to: 5)
        #expect(moved.map(\.id) == Array(ids[1...]) + [ids[0]])
        #expect(moved.map(\.order) == Array(0..<5))
        // Drag the last seat to the top.
        let up = LobbyRules.moving(seats, from: IndexSet(integer: 4), to: 0)
        #expect(up.map(\.id) == [ids[4]] + Array(ids[0..<4]))
        // ⋯ → Move one step either way; the ends don't wrap.
        #expect(LobbyRules.moving(ids[1], by: 1, in: seats).map(\.id) == [ids[0], ids[2], ids[1], ids[3], ids[4]])
        #expect(LobbyRules.moving(ids[0], by: -1, in: seats).map(\.id) == ids)
        #expect(LobbyRules.moving(ids[4], by: 1, in: seats).map(\.id) == ids)
    }

    @Test("Run It Back rotates the first deal one seat clockwise")
    func rotation() {
        let ids = players(4).map(\.id)
        #expect(LobbyRules.rotatedFirstDealer(order: ids, previous: ids[0]) == ids[1])
        #expect(LobbyRules.rotatedFirstDealer(order: ids, previous: ids[3]) == ids[0])
        #expect(LobbyRules.rotatedFirstDealer(order: ids, previous: nil) == ids[0])
    }

    // MARK: Role lines

    @Test("Role lines match mockup frame 5")
    func roleLines() {
        let seats = players(4)
        let host = seats[0].id
        var ben = seats[2]
        ben.gamesPlayed = 4
        var cleo = seats[3]
        cleo.gamesPlayed = 12
        let sam = guest("Sam", reporter: ben.id)
        let all = LobbyRules.renumbered([seats[0], seats[1], ben, cleo, sam])
        let config = GameConfig()
        func line(_ seat: Seat, open: Bool = false, played: Int? = nil) -> SeatRoleLine {
            LobbyRules.roleLine(for: seat, in: all, host: host, config: config, me: host, isOpen: open, playedTogether: played)
        }
        #expect(line(seats[0]) == .host(isScorekeeper: true))
        #expect(line(seats[0]).text == "Host · Scorekeeper")
        #expect(line(seats[1], played: 17).text == "Played 17 together")
        #expect(line(ben) == .meter(gamesPlayed: 4))
        #expect(line(ben).text == "4 of 10")
        #expect(line(cleo, open: true) == .waitingForPhone)
        #expect(line(cleo, open: true).text == "Seat saved · waiting for their phone")
        #expect(line(sam).text == "P2 reports for Sam")
        #expect(line(cleo) == .neverPlayed)

        let selfReport = GameConfig(scoringMode: .selfReport)
        #expect(LobbyRules.roleLine(for: seats[0], in: all, host: host, config: selfReport, me: host, isOpen: false, playedTogether: nil) == .host(isScorekeeper: false))
        let keeper = GameConfig(scorekeeperSeat: seats[1].id)
        #expect(LobbyRules.roleLine(for: seats[1], in: all, host: host, config: keeper, me: host, isOpen: false, playedTogether: 3) == .scorekeeper)
    }
}
