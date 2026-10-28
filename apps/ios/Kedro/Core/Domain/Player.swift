import Foundation

/// A public player profile, as returned by `GET /v1/players/me` and `PUT /v1/players/me`.
nonisolated struct Player: Hashable, Sendable, Codable, Identifiable {
    var id: PlayerID
    var displayName: String
    var handle: Handle
    var avatar: Avatar
    /// The title the player chose to display (a `TI-xx` copy ID), or nil for none.
    var titleID: String?
    var createdAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, displayName, handle, avatar, createdAt
        case titleID = "titleId"
    }

    var summary: PlayerSummary {
        PlayerSummary(id: id, displayName: displayName, handle: handle, avatar: avatar, titleID: titleID)
    }
}

/// The compact form of a player used in lists, search results and nearby tables
/// (`GET /v1/players/search` → `{players:[PlayerSummary]}`).
nonisolated struct PlayerSummary: Hashable, Sendable, Codable, Identifiable {
    var id: PlayerID
    var displayName: String
    var handle: Handle
    var avatar: Avatar
    /// Displayed title (`TI-xx` copy ID), if any.
    var titleID: String?
    /// Finished, non-abandoned games. Drives the 5-step meter and learner hints. Optional because
    /// not every source knows it.
    var gamesPlayed: Int?

    private enum CodingKeys: String, CodingKey {
        case id, displayName, handle, avatar, gamesPlayed
        case titleID = "titleId"
    }

    var ref: PlayerRef { .player(id) }
    var seatID: SeatID { ref.seatID }
}
