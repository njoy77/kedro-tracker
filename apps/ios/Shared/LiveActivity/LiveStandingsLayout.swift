import Foundation

/// A line in a truncated standings list: a row, or the `···` gap before your own row.
nonisolated enum LiveRowSlot: Hashable, Sendable, Identifiable {
    case row(LiveStandingRow)
    case gap

    var id: String {
        switch self {
        case .row(let row): row.id
        case .gap: "gap"
        }
    }

    var row: LiveStandingRow? {
        if case .row(let row) = self { row } else { nil }
    }
}

/// Which rows the Live Activity shows (design §13.2).
///
/// Rows are in standings order (best first). Positions, not rank numbers, decide what fits, so a
/// shared rank never pushes the list past its limit.
nonisolated enum LiveStandingsLayout {
    /// The Lock Screen's limit.
    static let lockScreenLimit = 5
    /// The expanded Island shows the top 3 plus you.
    static let expandedTop = 3

    /// Lock Screen truncation: if you're in the top 5 (or you're watching, or there are 5 or fewer
    /// seats), ranks 1–5. Otherwise ranks 1–4, `···`, then your row with your true rank.
    static func lockScreen(_ rows: [LiveStandingRow], limit: Int = lockScreenLimit) -> [LiveRowSlot] {
        guard limit > 1, rows.count > limit else { return rows.prefix(max(limit, 0)).map(LiveRowSlot.row) }
        guard let mine = rows.firstIndex(where: \.isMe), mine >= limit else {
            return rows.prefix(limit).map(LiveRowSlot.row)
        }
        return rows.prefix(limit - 1).map(LiveRowSlot.row) + [.gap, .row(rows[mine])]
    }

    /// Expanded Island: the top 3, plus your row (after a `···` gap if it doesn't follow on).
    static func expanded(_ rows: [LiveStandingRow], top: Int = expandedTop) -> [LiveRowSlot] {
        let head = rows.prefix(top).map(LiveRowSlot.row)
        guard let mine = rows.firstIndex(where: \.isMe), mine >= top else { return head }
        return head + (mine > top ? [.gap] : []) + [.row(rows[mine])]
    }
}
