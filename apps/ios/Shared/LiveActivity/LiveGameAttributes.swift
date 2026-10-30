import ActivityKit
import Foundation

/// The live game's Live Activity (design §13.2), shared by the app (which starts and updates it)
/// and KedroWidgets (which draws it).
///
/// Every string is rendered by the app in the player's language level before it gets here, so the
/// extension never needs the copy deck. The server's broadcast pushes (APNs channel per game) must
/// send the same `ContentState` JSON; the shape is documented on each type and pinned by
/// `LiveActivityContentTests`.
nonisolated struct LiveGameAttributes: ActivityAttributes {
    /// The game (`GameID`, lowercase UUID string).
    var gameID: String
    /// "Cold Deck" (real casing; Bebas renders it uppercase).
    var tableWord: String
    /// This phone's seat (`SeatID` raw value, `p:<uuid>` / `g:<uuid>`), nil for watchers.
    var mySeatID: String?

    /// What changes during the game. Kept well under ActivityKit's 4 KB payload limit: 8 rows of
    /// short strings plus a few lines.
    struct ContentState: Codable, Hashable, Sendable {
        var phase: LiveGamePhase
        /// The round being played (the last one once all are in).
        var roundNumber: Int
        var plannedRounds: Int
        /// "ROUND 6 OF 8 · NOAH DEALS" (literal). Without a dealer: "ROUND 6 OF 8".
        var metadataLine: String
        /// Every seat, best first (the fold's standings order).
        var rows: [LiveStandingRow]
        /// The last round's fact line ("Round 5. Noah knocked on 2."), nil before Round 1.
        var factLine: String?
        /// "Noah knocked · last turns" (K-23) while a live knock is marked; replaces the fact line.
        var liveKnockLine: String?
        /// "Last update 9:46 · Open Kedro to catch up" (N-06), shown once the content is stale.
        var staleLine: String
        /// The button on the Lock Screen and in the expanded Island, nil for watchers and finished games.
        var action: LiveActivityButton?
        /// When the app (or server) produced this content.
        var updatedAt: Date

        /// The live knock line if a knock is marked, else the fact line.
        var statusLine: String? { liveKnockLine ?? factLine }

        /// This phone's row.
        var myRow: LiveStandingRow? { rows.first(where: \.isMe) }

        /// The leading row(s): the first row, or every row sharing the lead.
        var leaders: [LiveStandingRow] { rows.filter(\.isLeader) }

        /// "R6/8" for the compact Island.
        var compactRound: String { "R\(roundNumber)/\(plannedRounds)" }
    }
}

/// Where the game is. JSON: `"active"` | `"finished"` | `"abandoned"`.
nonisolated enum LiveGamePhase: String, Codable, Hashable, Sendable {
    case active
    case finished
    case abandoned
}

/// One row of the Live Activity standings.
///
/// JSON: `{"id":"p:…","name":"Ana","rank":2,"rankLabel":"2","ordinal":"2nd","score":"29",
/// "delta":"+9","isMe":false,"isLeader":false,"isDealer":true,"avatar":{…},
/// "accessibilityLabel":"Ana, 2nd place, 29 points, last round plus 9"}` plus `outcome` for the
/// last round's knocker.
nonisolated struct LiveStandingRow: Codable, Hashable, Sendable, Identifiable {
    /// `SeatID` raw value.
    var id: String
    /// Real casing.
    var name: String
    /// Competition rank position (1-based; shared ranks repeat).
    var rank: Int
    /// "1", "2=".
    var rankLabel: String
    /// "1st", "2nd" (the Island's "1st · 26").
    var ordinal: String
    /// Cumulative total with a true minus ("26", "−4").
    var score: String
    /// The last round in its shortest honest form: "+9" for everyone but the knocker; for the
    /// knocker the math next to the outcome glyph ("−10", "5", "2 + 10"). nil before Round 1.
    var delta: String?
    /// Set only for the last round's knocker; drawn as a glyph next to `delta`.
    var outcome: LiveKnockOutcome?
    var isMe: Bool
    var isLeader: Bool
    var isDealer: Bool
    var avatar: LiveAvatar
    /// One VoiceOver element per row (design §14).
    var accessibilityLabel: String
}

/// The knock outcome glyphs (design §3.6). JSON: `"landed"` | `"tied"` | `"failed"`.
nonisolated enum LiveKnockOutcome: String, Codable, Hashable, Sendable {
    case landed, tied, failed

    var systemImage: String {
        switch self {
        case .landed: "checkmark"
        case .tied: "equal"
        case .failed: "xmark"
        }
    }
}

/// A 20 pt avatar the extension can draw without the network: photos fall back to the initial.
///
/// JSON: `{"emoji":{"emoji":"🦊","colorIndex":0}}`, `{"curated":{"id":"bull"}}`,
/// `{"initial":{"letter":"S","isGuest":true}}`.
nonisolated enum LiveAvatar: Codable, Hashable, Sendable {
    case emoji(emoji: String, colorIndex: Int)
    /// A `CuratedAvatarID` raw value.
    case curated(id: String)
    case initial(letter: String, isGuest: Bool)
}

/// The App Intent button on the Live Activity. JSON: `{"kind":"recordRound","title":"Record Round 6"}`.
nonisolated struct LiveActivityButton: Codable, Hashable, Sendable {
    var kind: LiveActivityAction
    /// Literal button text ("Record Round 6", "Report Your Hand").
    var title: String
}
