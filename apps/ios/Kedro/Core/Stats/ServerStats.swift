import Foundation
import Observation
import OSLog

/// The server's side of stats (PRD §3.3, §5.1, §5.3; design §12.4): both boards, the records, and
/// other players' ratings, ranks and lifetime numbers, computed once from every finished game on the
/// server so every phone shows the same thing for the same person.
///
/// The phone's own `StatsSnapshot` only sees games stored on this phone, which is right for
/// rivalries and your own detail screens, but not for "everyone", for someone you barely know,
/// or for the Played With board: only the server knows which of the guests at your old tables
/// have since claimed their history onto an account. Screens prefer these values when they're loaded and fall back to the local ones
/// offline or without an account.
@Observable
final class ServerStats {
    static let shared = ServerStats()

    /// Global boards by sort, as last fetched.
    private(set) var global: [LeaderboardSort: Leaderboard] = [:]
    /// Played With boards by sort, as last fetched (for the signed-in viewer).
    private(set) var playedWith: [LeaderboardSort: Leaderboard] = [:]
    /// Records boards by scope and kind, as last fetched.
    private(set) var records: [LeaderboardScope: [RecordKind: [RecordEntry]]] = [:]
    /// Profiles by player, as last fetched.
    private(set) var profiles: [PlayerID: PlayerProfileResponse] = [:]

    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "ServerStats")

    /// How long a fetched value is fresh enough not to ask again.
    static let freshFor: TimeInterval = 60

    /// Fetches a board for a scope and sort (no-op without an account, or while fresh).
    func load(_ scope: LeaderboardScope, api: APIClient, sort: LeaderboardSort, viewer: PlayerRef?, force: Bool = false) async {
        let key = "\(scope.rawValue).\(sort.rawValue)"
        guard force || isStale(key), await api.hasAccount() else { return }
        do {
            let response = try await api.leaderboard(scope: scope.rawValue, sort: sort.rawValue)
            let board = Self.leaderboard(from: response, scope: scope, sort: sort, viewer: viewer)
            switch scope {
            case .global: global[sort] = board
            case .playedWith: playedWith[sort] = board
            }
            fetchedAt[key] = .now
        } catch {
            log.info("\(scope.rawValue) board not loaded: \(String(describing: error), privacy: .public)")
        }
    }

    /// The fetched board for a scope and sort, if any.
    func board(_ scope: LeaderboardScope, sort: LeaderboardSort) -> Leaderboard? {
        switch scope {
        case .global: global[sort]
        case .playedWith: playedWith[sort]
        }
    }

    /// Fetches every record's top holders for a scope (no-op without an account, or while fresh).
    func loadRecords(_ scope: LeaderboardScope, api: APIClient, force: Bool = false) async {
        let key = "records.\(scope.rawValue)"
        guard force || isStale(key), await api.hasAccount() else { return }
        do {
            let response = try await api.records(scope: scope.rawValue, limit: RecordBoardView.limit)
            records[scope] = Self.records(from: response)
            fetchedAt[key] = .now
        } catch {
            log.info("Records not loaded: \(String(describing: error), privacy: .public)")
        }
    }

    /// The fetched top holders of a record in a scope, if any were fetched.
    func records(_ kind: RecordKind, scope: LeaderboardScope) -> [RecordEntry]? {
        records[scope].map { $0[kind] ?? [] }
    }

    /// Fetches a player's server profile (players only; guests have none).
    func loadProfile(api: APIClient, player: PlayerRef, force: Bool = false) async {
        guard let id = player.playerID else { return }
        let key = "profile.\(id.uuidString)"
        guard force || isStale(key), await api.hasAccount() else { return }
        do {
            profiles[id] = try await api.playerProfile(id)
            fetchedAt[key] = .now
        } catch {
            log.info("Profile not loaded: \(String(describing: error), privacy: .public)")
        }
    }

    func profile(_ player: PlayerRef) -> PlayerProfileResponse? {
        player.playerID.flatMap { profiles[$0] }
    }

    private func isStale(_ key: String) -> Bool {
        fetchedAt[key].map { Date.now.timeIntervalSince($0) > Self.freshFor } ?? true
    }

    // MARK: Mapping

    /// The server's records as the same `RecordEntry` rows the Board renders for local records.
    nonisolated static func records(from response: RecordsResponse) -> [RecordKind: [RecordEntry]] {
        var result: [RecordKind: [RecordEntry]] = [:]
        for record in response.records {
            guard let kind = RecordKind(rawValue: record.kind) else { continue }
            result[kind] = record.rows.map { row in
                let player = row.player
                return RecordEntry(
                    rank: row.rank,
                    ref: player.ref,
                    identity: StatsParticipant(ref: player.ref, seatedAs: player.ref, name: player.displayName, avatar: player.avatar, handle: player.handle, titleID: player.titleID),
                    value: row.value,
                    gameID: row.game?.gameId,
                    tableWord: row.game?.tableWord,
                    date: row.game?.finishedAt
                )
            }
        }
        return result
    }

    /// The server board as the same `Leaderboard` the Board renders for local scopes.
    nonisolated static func leaderboard(from response: LeaderboardResponse, scope: LeaderboardScope = .global, sort: LeaderboardSort, viewer: PlayerRef?) -> Leaderboard {
        let rankCounts = Dictionary(response.rows.compactMap(\.rank).map { ($0, 1) }, uniquingKeysWith: +)
        func identity(_ player: PlayerSummary) -> StatsParticipant {
            StatsParticipant(ref: player.ref, seatedAs: player.ref, name: player.displayName, avatar: player.avatar, handle: player.handle, titleID: player.titleID)
        }
        let rows = response.rows.map { row -> LeaderboardRow in
            let value = row.value ?? Double(row.rating)
            return LeaderboardRow(
                ref: row.player.ref,
                identity: identity(row.player),
                rank: row.rank.map { Rank(position: $0, isShared: (rankCounts[$0] ?? 0) > 1) },
                value: value,
                valueText: sort.format(value),
                gamesPlayed: row.gamesPlayed,
                knocks: row.knocks,
                isViewer: row.isMe || row.player.ref == viewer,
                isNew: false,
                lastRatingDelta: nil
            )
        }
        let unranked = response.notYetRanked.map { row in
            UnrankedRow(ref: row.player.ref, identity: identity(row.player), gamesPlayed: row.gamesPlayed, isViewer: row.isMe || row.player.ref == viewer)
        }
        return Leaderboard(
            scope: scope, sort: sort,
            ranked: rows.filter { $0.rank != nil },
            belowMinimum: rows.filter { $0.rank == nil },
            notYetRanked: unranked,
            viewer: viewer,
            closeRace: nil
        )
    }
}
