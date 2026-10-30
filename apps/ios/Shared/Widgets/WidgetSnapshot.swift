import Foundation

/// What the home and Lock Screen widgets show (design §13.3), written to the app group by the app
/// when a game finishes (and on claims) and read by KedroWidgets. Widgets never compute stats.
///
/// Strings are rendered in the player's language level by the app. JSON (sorted keys, ISO 8601):
/// `{"version":1,"generatedAt":"…","playerName":"Noah","standing":{…},"rivalry":{…},"nextBadge":{…}}`.
nonisolated struct WidgetSnapshot: Codable, Hashable, Sendable {
    static let currentVersion = 1

    var version: Int = Self.currentVersion
    var generatedAt: Date
    var playerName: String
    var standing: StandingSnapshot?
    var rivalry: RivalrySnapshot?
    var nextBadge: BadgeSnapshot?

    /// Shown when nothing has been written yet (fresh install, or the widget gallery).
    static let empty = WidgetSnapshot(generatedAt: .distantPast, playerName: "", standing: nil, rivalry: nil, nextBadge: nil)
}

/// The Standing widget: rank, rating and weekly movement, or the 5-step meter before game 5.
nonisolated struct StandingSnapshot: Codable, Hashable, Sendable {
    /// Games needed to get a rank (PRD: ranked after 5 finished games).
    static let gamesToRank = 5

    /// nil until ranked.
    var rank: Int?
    /// "Global" or "Played With" (literal).
    var scopeLabel: String
    /// nil until ranked.
    var rating: Int?
    /// Rank places gained (positive) or lost (negative) in the last 7 days.
    var weeklyMovement: Int
    var gamesPlayed: Int

    var isRanked: Bool { rank != nil && rating != nil }

    /// Meter steps filled before ranking (0–5).
    var meterSteps: Int { min(max(gamesPlayed, 0), Self.gamesToRank) }
}

/// The Rivalry widget: "You vs Ana · 5–12" plus the rivalry line.
nonisolated struct RivalrySnapshot: Codable, Hashable, Sendable {
    var rivalName: String
    var rivalAvatar: LiveAvatar
    var myAvatar: LiveAvatar
    /// Shared games where you finished ahead.
    var myWins: Int
    /// Shared games where they finished ahead.
    var theirWins: Int
    /// R-06 / R-03 / R-04 in the player's level.
    var line: String
}

/// The Next Badge widget: the closest badge and its progress.
nonisolated struct BadgeSnapshot: Codable, Hashable, Sendable {
    var badgeID: String
    /// Literal badge name ("Three-Peat").
    var name: String
    var tier: BadgeTierSnapshot
    var progress: Int
    var target: Int
    /// "1 of 3 wins in a row".
    var progressLine: String

    var fraction: Double { target > 0 ? min(1, Double(progress) / Double(target)) : 0 }
}

/// Badge coin rims (design §12.6). JSON: `"silver"` | `"red"` | `"gold"`.
nonisolated enum BadgeTierSnapshot: String, Codable, Hashable, Sendable {
    case silver, red, gold
}

/// Reads and writes the widget snapshot in the app group container.
nonisolated struct WidgetSnapshotStore: Sendable {
    static let fileName = "widget-snapshot.json"

    /// The snapshot file; nil without an app group (then nothing is shared).
    let fileURL: URL?

    init(fileURL: URL? = KedroAppGroup.containerURL?.appending(path: Self.fileName)) {
        self.fileURL = fileURL
    }

    func load() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let snapshot = try? SharedJSON.decoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version <= WidgetSnapshot.currentVersion
        else { return nil }
        return snapshot
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        guard let fileURL else { return }
        let data = try SharedJSON.encoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}

/// Widget kinds, shared so the app can reload them by name.
nonisolated enum KedroWidgetKind {
    static let standing = "KedroStanding"
    static let rivalry = "KedroRivalry"
    static let nextBadge = "KedroNextBadge"
    static let all = [standing, rivalry, nextBadge]
}
