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
    /// The Lock Screen's limit, in lines (the `···` gap counts): iOS cuts a Lock Screen Live
    /// Activity off at about 160 points, and the round, Rules and Record Round must stay in view.
    static let lockScreenLimit = 4
    /// The expanded Island shows the top 3 plus you.
    static let expandedTop = 3

    /// Lock Screen truncation, `limit` lines in all: if you're in the top 4 (or you're watching,
    /// or there are 4 or fewer seats), ranks 1–4. Otherwise ranks 1–2, `···`, then your row with
    /// your true rank.
    static func lockScreen(_ rows: [LiveStandingRow], limit: Int = lockScreenLimit) -> [LiveRowSlot] {
        guard limit > 2, rows.count > limit else { return rows.prefix(max(limit, 0)).map(LiveRowSlot.row) }
        guard let mine = rows.firstIndex(where: \.isMe), mine >= limit else {
            return rows.prefix(limit).map(LiveRowSlot.row)
        }
        return rows.prefix(limit - 2).map(LiveRowSlot.row) + [.gap, .row(rows[mine])]
    }

    /// Expanded Island: the top 3, plus your row (after a `···` gap if it doesn't follow on).
    static func expanded(_ rows: [LiveStandingRow], top: Int = expandedTop) -> [LiveRowSlot] {
        let head = rows.prefix(top).map(LiveRowSlot.row)
        guard let mine = rows.firstIndex(where: \.isMe), mine >= top else { return head }
        return head + (mine > top ? [.gap] : []) + [.row(rows[mine])]
    }
}
