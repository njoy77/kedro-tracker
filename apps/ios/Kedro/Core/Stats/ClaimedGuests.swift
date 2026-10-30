import Foundation
import Observation

/// Guest identities that count as this phone's person (PRD §3.2): guests the account claimed
/// (from `POST /v1/claims`, or listed by `GET /v1/players/me/games` on a new phone), and a seat
/// the host typed in that this phone took over ("Is this Sam? · Yes, that's me", design §5.7).
///
/// Op logs keep the guest seat as it was, so stats map these guests onto the viewer
/// (`StatsOptions.aliases`, applied app-wide by `.appServices()`): the history counts from game 1
/// and doesn't split across two identities.
@Observable
final class ClaimedGuests {
    static let shared = ClaimedGuests()
    static let defaultsKey = "kedro.claimedGuests"

    private(set) var guestIDs: Set<GuestID>

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        guestIDs = Set(stored.compactMap(GuestID.init(uuidString:)))
    }

    func record(_ ids: some Sequence<GuestID>) {
        let merged = guestIDs.union(ids)
        guard merged != guestIDs else { return }
        guestIDs = merged
        defaults.set(merged.map(\.uuidString).sorted(), forKey: Self.defaultsKey)
    }

    /// The stats aliases for a viewer: every claimed guest counts as them.
    func aliases(for viewer: PlayerRef?) -> [PlayerRef: PlayerRef] {
        guard let viewer else { return [:] }
        return Dictionary(uniqueKeysWithValues: guestIDs.map { PlayerRef.guest($0) }.filter { $0 != viewer }.map { ($0, viewer) })
    }
}
