import Foundation

/// Picks the one phone that plays a table's shared sounds, so eight phones don't go off at once
/// (design §3.8).
///
/// Order: the latest `TableSpeakerClaimed` (a phone in display mode claims it on entering, and
/// anyone can claim it from ⋯ → "Be the table speaker"), otherwise the scorekeeper's phone,
/// otherwise the host's. A phone set to "Never" doesn't play shared moments even when elected.
nonisolated enum TableSpeaker {
    /// The phone elected by the game state, if any phone is linked to the deciding seat.
    static func device(for state: GameState) -> DeviceID? {
        if let claimed = state.tableSpeaker { return claimed }
        if let scorekeeper = state.scorekeeper, let device = state.seat(scorekeeper)?.deviceID { return device }
        if let host = state.hostSeat, let device = state.seat(host)?.deviceID { return device }
        return nil
    }

    /// Whether this phone plays the shared moments.
    static func isThisPhone(_ device: DeviceID, state: GameState, preference: TableSpeakerPreference) -> Bool {
        switch preference {
        case .never: false
        case .always, .automatic: Self.device(for: state) == device
        }
    }

    /// Whether this phone should claim the speaker on joining: it's set to "This Phone", the game
    /// is live, and nobody has claimed it explicitly yet. It never takes the speaker back from an
    /// explicit claim, so two "This Phone" phones can't fight over it.
    static func shouldClaim(_ device: DeviceID, state: GameState, preference: TableSpeakerPreference) -> Bool {
        preference == .always && state.status.isLive && state.tableSpeaker == nil && Self.device(for: state) != device
    }
}
