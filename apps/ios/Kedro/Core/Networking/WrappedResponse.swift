import Foundation

/// `GET /v1/players/me/wrapped?year=&tz=` (packages/shared `WrappedResponse`): a year's recap
/// replayed on the server from every game the player has finished, so a phone that only holds some
/// of them (a new phone, games logged from someone else's) still gets the whole year. `summary` is
/// present only once the year is available (10+ games, from December 1 in `tz`).
nonisolated struct WrappedResponse: Codable, Hashable, Sendable {
    var year: Int
    var availability: Availability
    var summary: Summary?

    /// `{"kind":"available"}`, `{"kind":"needsGames","played":4,"needed":10}` or
    /// `{"kind":"arrives","at":"2026-12-01T05:00:00Z"}`.
    nonisolated struct Availability: Codable, Hashable, Sendable {
        var kind: String
        var played: Int?
        var needed: Int?
        var at: Date?

        /// nil for a kind this app doesn't know (a newer server's).
        var value: WrappedAvailability? {
            switch kind {
            case "available": .available
            case "needsGames": .needsGames(played: played ?? 0, needed: needed ?? WrappedSummary.minimumGames)
            case "arrives": at.map(WrappedAvailability.arrives)
            default: nil
            }
        }
    }

    nonisolated struct Person: Codable, Hashable, Sendable {
        var kind: String
        var id: UUID
        var displayName: String

        var ref: PlayerRef { kind == "guest" ? .guest(GuestID(id)) : .player(PlayerID(id)) }
    }

    nonisolated struct Counted: Codable, Hashable, Sendable {
        var person: Person
        var count: Int
    }

    nonisolated struct Knock: Codable, Hashable, Sendable {
        var gameId: GameID
        var tableWord: String
        var date: Date
        var roundNumber: Int
        var hand: Int
        var lowestOther: Int?
    }

    nonisolated struct Shame: Codable, Hashable, Sendable {
        var category: String
        var person: Person
        var gameId: GameID
        var tableWord: String
        var finishedAt: Date
        var roundNumber: Int?
        var value: Int
        var hand: Int?
        var low: Int?
        var finishPosition: Int?
    }

    nonisolated struct Point: Codable, Hashable, Sendable {
        var date: Date
        var rating: Double
    }

    nonisolated struct Persona: Codable, Hashable, Sendable {
        var id: String
    }

    nonisolated struct Summary: Codable, Hashable, Sendable {
        var year: Int
        var games: Int
        var rounds: Int
        var hours: Double
        var people: Int
        var wins: Int
        var winRate: Double
        var finishes: [String: Int]
        var isWinRateHigh: Bool
        var ratingLine: [Point]
        var ratingStart: Int
        var ratingPeak: Int
        var ratingNow: Int
        var currentRank: Int?
        var knocks: Int
        var knockSuccess: Double
        var favoriteKnockValue: Int?
        var bestKnock: Knock?
        var worstKnock: Knock?
        var nemesis: Counted?
        var victim: Counted?
        var redKings: Int
        var ghostHands: Int
        var biggestHand: Int
        var tauntsSent: Int
        var favoriteTaunt: TauntContent?
        var mostTaunted: Counted?
        var badges: [PlayerProgressionResponse.EarnedBadge]
        var titles: [String]
        var shame: [Shame]
        var persona: Persona
    }

    /// The server's recap as the `WrappedSummary` the story cards render, for `identity` (the
    /// signed-in player as this phone knows them). Badges, titles and Hall of Shame categories
    /// this app doesn't know are skipped; an unknown persona reads as The Wildcard.
    func wrappedSummary(for identity: StatsParticipant) -> WrappedSummary? {
        guard let summary else { return nil }
        func person(_ counted: Counted?) -> WrappedSummary.Person? {
            counted.map { WrappedSummary.Person(ref: $0.person.ref, name: $0.person.displayName, count: $0.count) }
        }
        func knock(_ knock: Knock?, outcome: KnockOutcome) -> KnockEvent? {
            knock.map {
                KnockEvent(gameID: $0.gameId, gameIndex: 0, date: $0.date, tableWord: $0.tableWord, roundNumber: $0.roundNumber, hand: $0.hand, lowestOther: $0.lowestOther, outcome: outcome)
            }
        }
        let shame = summary.shame.compactMap { entry -> ShameEntry? in
            guard let category = ShameCategory(rawValue: entry.category) else { return nil }
            let ref = entry.person.ref
            return ShameEntry(
                category: category, player: ref,
                identity: ref == identity.ref ? identity : StatsParticipant(ref: ref, seatedAs: ref, name: entry.person.displayName),
                gameID: entry.gameId, gameIndex: 0, tableWord: entry.tableWord, date: entry.finishedAt,
                roundNumber: entry.roundNumber, value: entry.value, hand: entry.hand, low: entry.low,
                finish: entry.finishPosition.map { Rank(position: $0, isShared: false) }
            )
        }
        return WrappedSummary(
            year: summary.year, player: identity.ref, identity: identity,
            games: summary.games, rounds: summary.rounds, hours: summary.hours, people: summary.people,
            wins: summary.wins, winRate: summary.winRate,
            finishes: Dictionary(summary.finishes.compactMap { key, value in Int(key).map { ($0, value) } }, uniquingKeysWith: +),
            isWinRateHigh: summary.isWinRateHigh,
            ratingLine: summary.ratingLine.enumerated().map { RatingPoint(gameIndex: $0.offset, date: $0.element.date, rating: $0.element.rating) },
            ratingStart: summary.ratingStart, ratingPeak: summary.ratingPeak, ratingNow: summary.ratingNow,
            currentRank: summary.currentRank.map { Rank(position: $0, isShared: false) },
            knocks: summary.knocks, knockSuccess: summary.knockSuccess, favoriteKnockValue: summary.favoriteKnockValue,
            bestKnock: knock(summary.bestKnock, outcome: .landed),
            worstKnock: knock(summary.worstKnock, outcome: .failed),
            nemesis: person(summary.nemesis), victim: person(summary.victim),
            redKings: summary.redKings, ghostHands: summary.ghostHands, biggestHand: summary.biggestHand,
            tauntsSent: summary.tauntsSent, favoriteTaunt: summary.favoriteTaunt, mostTaunted: person(summary.mostTaunted),
            badges: summary.badges.compactMap { earned in
                BadgeID(rawValue: earned.badge).map {
                    BadgeAward(badge: $0, gameID: earned.gameId, tableWord: earned.tableWord, roundNumber: earned.roundNumber, date: earned.earnedAt)
                }
            },
            titles: summary.titles.compactMap(TitleID.init(rawValue:)),
            shame: shame,
            persona: WrappedPersona(rawValue: summary.persona.id) ?? .wildcard
        )
    }
}

extension WrappedAvailability {
    /// The further along of two answers for the same year (the phone's and the server's): open
    /// beats waiting for December, which beats needing games (then whoever counted more).
    func furthest(_ other: WrappedAvailability?) -> WrappedAvailability {
        guard let other else { return self }
        switch (self, other) {
        case (.available, _): return self
        case (_, .available): return other
        case (.arrives, _): return self
        case (_, .arrives): return other
        case let (.needsGames(mine, _), .needsGames(theirs, _)): return theirs > mine ? other : self
        }
    }
}
