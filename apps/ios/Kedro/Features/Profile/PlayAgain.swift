import Foundation

extension AppModel {
    /// "Play Again with {name}" (design §12.2–§12.3): opens a new table with the same settings as
    /// last time and the other person already seated, then shows it.
    func playAgain(with people: [StatsParticipant]) async throws {
        let others = people
            .filter { $0.ref != profile?.identity }
            .enumerated()
            .map { offset, person in
                Seat(
                    player: person.ref, displayName: person.name, order: offset + 1,
                    handle: person.handle, avatar: person.avatar, titleID: person.titleID
                )
            }
        let config = GameConfig(plannedRounds: preferences.lastPlannedRounds, scoringMode: preferences.lastScoringMode)
        let session = try await createGame(config: config, others: others)
        startLiveGame(session, present: true)
    }
}
