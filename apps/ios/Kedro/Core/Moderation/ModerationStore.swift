import Foundation
import Observation
import OSLog

/// How long a mute lasts (design §8.3: "this game or always").
nonisolated enum MuteScope: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case thisGame, always

    var id: String { rawValue }

    /// Literal menu label.
    var title: String {
        switch self {
        case .thisGame: "This Game"
        case .always: "Always"
        }
    }
}

/// A report or block that still has to reach the server (they're applied on this phone at once).
nonisolated enum PendingModeration: Hashable, Sendable, Codable {
    case report(targetType: ReportTargetType, targetID: String, reason: ReportReason)
    case block(PlayerID)
    case unblock(PlayerID)
}

/// This phone's safeguards (design §8.3): reported taunts, mutes and blocks. Everything applies
/// locally the moment it's chosen and persists in `UserDefaults`; the server calls are queued in
/// `pending` and sent by `flush(using:)`.
///
/// People are identified by `SeatID`, which is derived from the person (`PlayerRef`) and is the
/// same in every game, so "mute always" and blocks follow them from table to table.
@Observable
final class ModerationStore {
    static let defaultsKey = "kedro.moderation"

    /// Taunts this phone reported: hidden for the reporter immediately (T-13).
    private(set) var reportedTaunts: Set<UUID> = []
    /// Muted everywhere.
    private(set) var mutedAlways: Set<SeatID> = []
    /// Muted for one game.
    private(set) var mutedInGame: [GameID: Set<SeatID>] = [:]
    /// Blocked people. Their taunts and receipts are hidden; the server keeps them from seating
    /// you, taunting you or sending you receipts.
    private(set) var blocked: Set<PlayerRef> = []
    /// Server calls still to make.
    private(set) var pending: [PendingModeration] = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isFlushing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            reportedTaunts = snapshot.reportedTaunts
            mutedAlways = snapshot.mutedAlways
            mutedInGame = snapshot.mutedInGame
            blocked = snapshot.blocked
            pending = snapshot.pending
        }
    }

    // MARK: Queries

    func isMuted(_ seat: SeatID, in game: GameID) -> Bool {
        mutedAlways.contains(seat) || mutedInGame[game]?.contains(seat) == true
    }

    /// The scope a person is muted with in this game, if any.
    func muteScope(of seat: SeatID, in game: GameID) -> MuteScope? {
        if mutedAlways.contains(seat) { return .always }
        if mutedInGame[game]?.contains(seat) == true { return .thisGame }
        return nil
    }

    func isBlocked(_ seat: SeatID) -> Bool {
        blocked.contains { $0.seatID == seat }
    }

    func isBlocked(_ person: PlayerRef) -> Bool { blocked.contains(person) }

    /// Whether this phone shows a taunt. Hidden when reported, when the sender is muted or
    /// blocked, or when it's custom and custom taunts are off here (Settings, or under 18).
    func hides(_ taunt: TauntRecord, in game: GameID, showsCustom: Bool) -> Bool {
        if taunt.isRetracted || reportedTaunts.contains(taunt.tauntId) { return true }
        if taunt.content.isCustom && !showsCustom { return true }
        guard let sender = taunt.from else { return false }
        return isMuted(sender, in: game) || isBlocked(sender)
    }

    /// Receipts from blocked or muted people are hidden ("Mutable per person", design §8.5).
    func hidesReceipt(from sender: SeatID, in game: GameID) -> Bool {
        isBlocked(sender) || isMuted(sender, in: game)
    }

    // MARK: Changes

    /// Hides the taunt now and queues the report (T-13).
    func report(_ taunt: TauntRecord, reason: ReportReason) {
        reportedTaunts.insert(taunt.tauntId)
        pending.append(.report(targetType: .taunt, targetID: taunt.tauntId.uuidString.lowercased(), reason: reason))
        save()
    }

    /// Reports a person (from a profile). Queued.
    func report(player: PlayerID, reason: ReportReason) {
        pending.append(.report(targetType: .player, targetID: player.uuidString.lowercased(), reason: reason))
        save()
    }

    /// Mute Their Taunts. The sender is never told (T-11).
    func mute(_ seat: SeatID, scope: MuteScope, in game: GameID) {
        switch scope {
        case .always:
            mutedAlways.insert(seat)
        case .thisGame:
            mutedInGame[game, default: []].insert(seat)
        }
        save()
    }

    /// Mute Their Taunts from a profile (no game): always.
    func muteAlways(_ seat: SeatID) {
        mutedAlways.insert(seat)
        save()
    }

    /// Lifts the "always" mute and, with a game, that game's mute.
    func unmute(_ seat: SeatID, in game: GameID?) {
        mutedAlways.remove(seat)
        if let game {
            mutedInGame[game]?.remove(seat)
            if mutedInGame[game]?.isEmpty == true { mutedInGame[game] = nil }
        }
        save()
    }

    /// Blocks a person. Guests are blocked on this phone only (the server has no account to block).
    func block(_ person: PlayerRef) {
        guard blocked.insert(person).inserted else { return }
        if let player = person.playerID {
            pending.removeAll { $0 == .unblock(player) }
            pending.append(.block(player))
        }
        save()
    }

    func unblock(_ person: PlayerRef) {
        guard blocked.remove(person) != nil else { return }
        if let player = person.playerID {
            let hadPendingBlock = pending.contains(.block(player))
            pending.removeAll { $0 == .block(player) }
            if !hadPendingBlock { pending.append(.unblock(player)) }
        }
        save()
    }

    // MARK: Server

    /// Sends queued reports and blocks, oldest first. Stops at the first failure (offline, signed
    /// out) and keeps the rest for next time.
    func flush(using api: any TrashTalkAPI) async {
        guard !isFlushing, !pending.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }
        while let next = pending.first {
            do {
                switch next {
                case let .report(targetType, targetID, reason):
                    try await api.report(targetType, targetID: targetID, reason: reason)
                case .block(let player):
                    try await api.block(player)
                case .unblock(let player):
                    try await api.unblock(player)
                }
                if pending.first == next { pending.removeFirst() }
                save()
            } catch {
                Logger(subsystem: "com.njoy77.kedro", category: "Moderation")
                    .info("Moderation sync paused: \(String(describing: error), privacy: .public)")
                return
            }
        }
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var reportedTaunts: Set<UUID>
        var mutedAlways: Set<SeatID>
        var mutedInGame: [GameID: Set<SeatID>]
        var blocked: Set<PlayerRef>
        var pending: [PendingModeration]
    }

    private func save() {
        let snapshot = Snapshot(
            reportedTaunts: reportedTaunts, mutedAlways: mutedAlways, mutedInGame: mutedInGame, blocked: blocked, pending: pending
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
