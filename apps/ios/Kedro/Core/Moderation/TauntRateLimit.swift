import Foundation

/// How many taunts a player has left this round (design §8.1, §8.3).
nonisolated struct TauntAllowance: Hashable, Sendable {
    var used: Int
    var customUsed: Int

    var remaining: Int { max(0, TauntRateLimit.perRound - used) }
    var canSend: Bool { remaining > 0 }
    var canSendCustom: Bool { canSend && customUsed < TauntRateLimit.customPerRound }
}

/// The taunt rate limits: 3 per player per round, of which at most 1 custom.
///
/// Counted from the operation log, so the count is the same after a relaunch and on every phone.
/// A sender is matched by seat, or by phone for watchers (who have no seat). Receiving phones
/// apply the same limit (`withinLimits`), so a modified client can't flood a table.
nonisolated enum TauntRateLimit {
    static let perRound = 3
    static let customPerRound = 1

    /// This sender's usage in a round.
    static func allowance(operations: [GameOperation], round: Int, seat: SeatID?, device: DeviceID) -> TauntAllowance {
        var seen: Set<UUID> = []
        var used = 0
        var customUsed = 0
        for operation in operations {
            guard case .tauntSent(let taunt) = operation.payload, taunt.roundNumber == round,
                  seen.insert(taunt.tauntId).inserted
            else { continue }
            let isMine = (seat != nil && taunt.from == seat) || (taunt.from == nil && operation.deviceId == device)
            guard isMine else { continue }
            used += 1
            if taunt.content.isCustom { customUsed += 1 }
        }
        return TauntAllowance(used: used, customUsed: customUsed)
    }

    /// The taunts that fit the limits, in order: per sender and round, the first 3, and of those
    /// at most 1 custom. Senders are keyed by seat, or by name for watchers.
    static func withinLimits(_ taunts: [TauntRecord]) -> [TauntRecord] {
        struct Key: Hashable {
            var round: Int
            var sender: String
        }
        var counts: [Key: TauntAllowance] = [:]
        return taunts.filter { taunt in
            let key = Key(round: taunt.roundNumber, sender: taunt.from?.rawValue ?? "watcher:\(taunt.fromName)")
            var allowance = counts[key] ?? TauntAllowance(used: 0, customUsed: 0)
            guard taunt.content.isCustom ? allowance.canSendCustom : allowance.canSend else { return false }
            allowance.used += 1
            if taunt.content.isCustom { allowance.customUsed += 1 }
            counts[key] = allowance
            return true
        }
    }
}
