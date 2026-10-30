import Foundation

/// Finding people to seat (design §5.6): Played With, Search Kedro, and guest suggestions.
/// The Networking agent implements a server-backed one in Core/Directory (search hits
/// `GET /v1/players/search?q=`); `LocalPlayerDirectory` answers from this phone's games.
protocol PlayerDirectory: AnyObject, Sendable {
    /// Any Kedro player by display name or @handle. Excludes blocked players.
    func search(_ query: String) async throws -> [PlayerSummary]

    /// Everyone you've shared a finished game with, most recent first.
    func playedWith() async throws -> [PlayedWith]

    /// Guests whose name matches, so one guest identity builds up history
    /// ("Sam · guest · 2 games with you").
    func guestSuggestions(matching name: String) async throws -> [GuestSuggestion]

    /// One player, if known.
    func player(_ id: PlayerID) async throws -> PlayerSummary?

    /// Every Kedro player A–Z, a page at a time (the Add Player list's "Everyone"). Pass the
    /// previous page's `next` to continue; nil starts from the top. Excludes blocked players.
    func everyone(after cursor: String?) async throws -> PlayerPage
}

extension PlayerDirectory {
    /// Without a server, "everyone" is everyone this phone has played with.
    func everyone(after cursor: String?) async throws -> PlayerPage {
        guard cursor == nil else { return PlayerPage(players: [], next: nil) }
        let players = try await playedWith().map(\.player)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return PlayerPage(players: players, next: nil)
    }
}

/// One page of `PlayerDirectory.everyone(after:)`.
nonisolated struct PlayerPage: Hashable, Sendable {
    var players: [PlayerSummary]
    /// The cursor for the next page; nil at the end.
    var next: String?
}

nonisolated struct PlayedWith: Hashable, Sendable, Identifiable {
    var player: PlayerSummary
    var gamesTogether: Int
    var lastPlayed: Date?

    var id: PlayerID { player.id }
}

nonisolated struct GuestSuggestion: Hashable, Sendable, Identifiable {
    var guestID: GuestID
    var name: String
    var gamesTogether: Int

    var id: GuestID { guestID }
}

/// A `PlayerDirectory` built from the games stored on this phone. Search only finds players
/// you've shared a table with; the server-backed directory finds everyone.
final class LocalPlayerDirectory: PlayerDirectory {
    private let store: any GameStore
    private let me: () -> PlayerRef?

    /// - Parameter me: Who's using the phone (excluded from results).
    init(store: any GameStore, me: @escaping () -> PlayerRef?) {
        self.store = store
        self.me = me
    }

    func search(_ query: String) async throws -> [PlayerSummary] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !needle.isEmpty else { return [] }
        return try await knownPlayers().values
            .map(\.summary)
            .filter { $0.displayName.lowercased().contains(needle) || $0.handle.rawValue.contains(needle) }
            .sorted { $0.displayName < $1.displayName }
    }

    func playedWith() async throws -> [PlayedWith] {
        try await knownPlayers().values
            .map { PlayedWith(player: $0.summary, gamesTogether: $0.games, lastPlayed: $0.lastPlayed) }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    func guestSuggestions(matching name: String) async throws -> [GuestSuggestion] {
        let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        var guests: [GuestID: GuestSuggestion] = [:]
        for game in try await store.finishedGames() {
            for seat in game.seats {
                guard case .guest(let id) = seat.player, seat.displayName.lowercased().hasPrefix(needle) else { continue }
                guests[id, default: GuestSuggestion(guestID: id, name: seat.displayName, gamesTogether: 0)].gamesTogether += 1
            }
        }
        return guests.values.sorted { $0.gamesTogether > $1.gamesTogether }
    }

    func player(_ id: PlayerID) async throws -> PlayerSummary? {
        try await knownPlayers()[id]?.summary
    }

    private struct Known {
        var summary: PlayerSummary
        var games: Int
        var lastPlayed: Date?
    }

    private func knownPlayers() async throws -> [PlayerID: Known] {
        let me = me()
        var known: [PlayerID: Known] = [:]
        for game in try await store.finishedGames() {
            if let me, game.seat(for: me) == nil { continue }
            for seat in game.seats {
                guard case .player(let id) = seat.player, seat.player != me, let handle = seat.handle else { continue }
                let summary = PlayerSummary(
                    id: id, displayName: seat.displayName, handle: handle,
                    avatar: seat.avatar ?? .curated(.spade), titleID: seat.titleID, gamesPlayed: seat.gamesPlayed
                )
                var entry = known[id] ?? Known(summary: summary, games: 0, lastPlayed: nil)
                entry.games += 1
                if (game.finishedAt ?? .distantPast) >= (entry.lastPlayed ?? .distantPast) {
                    entry.summary = summary
                    entry.lastPlayed = game.finishedAt
                }
                known[id] = entry
            }
        }
        return known
    }
}
