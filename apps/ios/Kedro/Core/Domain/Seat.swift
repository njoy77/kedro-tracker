import Foundation

/// A seat at a table: who sits there and where (design §5.6, §6.4).
///
/// Seats are ordered clockwise around the physical table by `order`, which is also the dealing
/// order: the deal passes to the next seat in `order` after every saved round.
///
/// JSON (inside `PlayerSeated.seat`; optional keys are omitted when nil):
/// `{"player":{"kind":"guest","id":"…"},"displayName":"Sam","order":4,"reporter":"p:…","gamesPlayed":2}`
/// plus, when set: `handle`, `avatar`, `deviceId`, `languageLevel`, `titleId`, `claimTokenHash`.
nonisolated struct Seat: Hashable, Sendable, Codable, Identifiable {
    /// The person in the seat. Determines `id`.
    var player: PlayerRef
    /// Name as shown at the table (real casing; Bebas renders it uppercase).
    var displayName: String
    /// Clockwise position, 0-based.
    var order: Int
    var handle: Handle?
    /// nil for guests (they render as an initial with a dashed ring).
    var avatar: Avatar?
    /// Self-report mode: the seat that reports for this one (guests without the app).
    var reporter: SeatID?
    /// The phone linked to this seat, once one has sat down. Used to attribute operations from
    /// phones without an account and to match a late phone to its seat.
    var deviceID: DeviceID?
    /// The seated phone's language level; the house voice is the lowest of these (design §4.1).
    var languageLevel: LanguageLevel?
    /// The player's displayed title (`TI-xx`), snapshotted when they sat down.
    var titleID: String?
    /// Finished games before this one, snapshotted when they sat down (learner hints, the rank meter).
    var gamesPlayed: Int?
    /// A guest seat sat in by the phone that owns that guest identity: the lowercase hex SHA-256
    /// of its claim token, so the server can match a later `POST /v1/claims` (never the token).
    var claimTokenHash: String?
    /// A late joiner's first round. Set by the fold, never taken from a phone's operation.
    var joinedRound: Int?
    /// A late joiner's score before their first round: the highest total at the table when they
    /// sat down. Set by the fold, never taken from a phone's operation.
    var startingScore: Int?

    var id: SeatID { player.seatID }

    /// The first round this seat plays (1 unless they joined late).
    var firstRound: Int { joinedRound ?? 1 }

    private enum CodingKeys: String, CodingKey {
        case player, displayName, order, handle, avatar, reporter, languageLevel, gamesPlayed, claimTokenHash
        case joinedRound, startingScore
        case deviceID = "deviceId"
        case titleID = "titleId"
    }

    var isGuest: Bool { player.isGuest }

    /// A player's first 3 games get teaching lines for their own bad outcomes (design §4.3).
    var isLearner: Bool { (gamesPlayed ?? 0) < 3 }

    /// First letter for guest and fallback avatars.
    var initial: String { displayName.first.map { String($0).uppercased() } ?? "?" }

    init(
        player: PlayerRef,
        displayName: String,
        order: Int,
        handle: Handle? = nil,
        avatar: Avatar? = nil,
        reporter: SeatID? = nil,
        deviceID: DeviceID? = nil,
        languageLevel: LanguageLevel? = nil,
        titleID: String? = nil,
        gamesPlayed: Int? = nil,
        claimTokenHash: String? = nil
    ) {
        self.player = player
        self.displayName = displayName
        self.order = order
        self.handle = handle
        self.avatar = avatar
        self.reporter = reporter
        self.deviceID = deviceID
        self.languageLevel = languageLevel
        self.titleID = titleID
        self.gamesPlayed = gamesPlayed
        self.claimTokenHash = claimTokenHash
    }

    /// A seat for a signed-up player.
    init(_ summary: PlayerSummary, order: Int, deviceID: DeviceID? = nil, languageLevel: LanguageLevel? = nil) {
        self.init(
            player: summary.ref,
            displayName: summary.displayName,
            order: order,
            handle: summary.handle,
            avatar: summary.avatar,
            deviceID: deviceID,
            languageLevel: languageLevel,
            titleID: summary.titleID,
            gamesPlayed: summary.gamesPlayed
        )
    }
}
