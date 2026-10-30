import Foundation
import OSLog

/// The server-backed `PlayerDirectory` (design §5.6).
///
/// - **Search Kedro** asks `GET /v1/players/search?q=` (display name or @handle, blocked players
///   excluded by the server) and caches every result. Offline or signed out, it answers from the
///   cache plus the players on this phone's games, so the lobby still finds the regulars.
/// - **Played With** asks `GET /v1/players/me/played-with`, which knows who claimed which guest
///   history (this phone's games still show those people as the guests they were). Offline, it's
///   derived from this phone's finished games, refreshed from the cache.
/// - **Guest suggestions** come from this phone's finished games.
/// - **Everyone** pages through `GET /v1/players` (A–Z, blocked players excluded) and caches
///   it; offline, it falls back to everyone this phone has played with.
/// - **player(_:)** answers from the cache first, then local games.
final class RemotePlayerDirectory: PlayerDirectory {
    private let api: APIClient
    private let local: any PlayerDirectory
    private let cache: PlayerCache
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Directory")

    /// Players the server excluded from a search lately, so a cached copy isn't resurrected.
    private var hiddenByServer: Set<PlayerID> = []

    /// - Parameters:
    ///   - local: Answers from stored games (`LocalPlayerDirectory`).
    init(api: APIClient, local: any PlayerDirectory, cache: PlayerCache = PlayerCache()) {
        self.api = api
        self.local = local
        self.cache = cache
    }

    static let minimumQueryLength = 2

    func search(_ query: String) async throws -> [PlayerSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        guard needle.count >= Self.minimumQueryLength else {
            return needle.isEmpty ? [] : try await offlineSearch(needle)
        }
        do {
            let players = try await api.searchPlayers(trimmed)
            cache.store(players)
            // Anyone the cache would match but the server didn't return is hidden (blocked, renamed).
            let returned = Set(players.map(\.id))
            hiddenByServer.formUnion(cache.matching(needle).map(\.id).filter { !returned.contains($0) })
            hiddenByServer.subtract(returned)
            return players
        } catch let error as APIError {
            log.info("Search fell back to this phone: \(String(describing: error), privacy: .public)")
            return try await offlineSearch(needle)
        }
    }

    func playedWith() async throws -> [PlayedWith] {
        do {
            let rows = try await api.playedWith()
            cache.store(rows.map(\.player))
            return rows
                .map { PlayedWith(player: $0.player, gamesTogether: $0.gamesTogether, lastPlayed: $0.lastPlayedAt) }
                .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        } catch let error as APIError {
            log.info("Played With fell back to this phone: \(String(describing: error), privacy: .public)")
        }
        return try await local.playedWith().map { entry in
            var entry = entry
            if let fresher = cache.player(entry.player.id) { entry.player = fresher }
            return entry
        }
    }

    func guestSuggestions(matching name: String) async throws -> [GuestSuggestion] {
        try await local.guestSuggestions(matching: name)
    }

    func everyone(after cursor: String?) async throws -> PlayerPage {
        do {
            let page = try await api.listPlayers(after: cursor)
            cache.store(page.players)
            return PlayerPage(players: page.players, next: page.next)
        } catch let error as APIError {
            log.info("Everyone fell back to this phone: \(String(describing: error), privacy: .public)")
            guard cursor == nil else { return PlayerPage(players: [], next: nil) }
            let players = try await playedWith().map(\.player)
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return PlayerPage(players: players, next: nil)
        }
    }

    func player(_ id: PlayerID) async throws -> PlayerSummary? {
        if let cached = cache.player(id) { return cached }
        return try await local.player(id)
    }

    /// Whether this phone's person has shared a finished game with a player (Sit Down vs Ask to
    /// Sit, nearby alerts).
    func hasPlayedWith(_ person: PlayerRef) async -> Bool {
        guard case .player(let id) = person else { return false }
        return ((try? await playedWith()) ?? []).contains { $0.player.id == id }
    }

    private func offlineSearch(_ needle: String) async throws -> [PlayerSummary] {
        var byID: [PlayerID: PlayerSummary] = [:]
        for player in try await local.search(needle) { byID[player.id] = player }
        for player in cache.matching(needle) where !hiddenByServer.contains(player.id) { byID[player.id] = player }
        return byID.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

/// Player summaries the server has returned, kept on disk (Caches) so search and the lobby work
/// offline. Capped; least recently seen players go first.
final class PlayerCache {
    private struct Entry: Codable {
        var player: PlayerSummary
        var seenAt: Date
    }

    static let capacity = 500

    private var entries: [PlayerID: Entry]
    private let url: URL?
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Directory")

    /// - Parameter url: nil keeps the cache in memory (tests, previews).
    init(url: URL? = URL.cachesDirectory.appending(path: "kedro-players.json")) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? KedroJSON.decoder().decode([Entry].self, from: data) {
            entries = Dictionary(saved.map { ($0.player.id, $0) }) { $0.seenAt > $1.seenAt ? $0 : $1 }
        } else {
            entries = [:]
        }
    }

    var count: Int { entries.count }

    func player(_ id: PlayerID) -> PlayerSummary? { entries[id]?.player }

    func store(_ players: [PlayerSummary], at date: Date = .now) {
        guard !players.isEmpty else { return }
        for player in players {
            entries[player.id] = Entry(player: player, seenAt: date)
        }
        if entries.count > Self.capacity {
            let keep = entries.values.sorted { $0.seenAt > $1.seenAt }.prefix(Self.capacity)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.player.id, $0) })
        }
        save()
    }

    /// Cached players whose display name or handle contains `needle` (lowercased, no "@").
    func matching(_ needle: String) -> [PlayerSummary] {
        entries.values.map(\.player).filter {
            $0.displayName.lowercased().contains(needle) || $0.handle.rawValue.contains(needle)
        }
    }

    private func save() {
        guard let url else { return }
        do {
            try KedroJSON.encoder().encode(Array(entries.values)).write(to: url, options: .atomic)
        } catch {
            log.error("Couldn't save the player cache: \(error.localizedDescription, privacy: .public)")
        }
    }
}
