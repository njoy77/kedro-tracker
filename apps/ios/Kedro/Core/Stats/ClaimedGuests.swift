import Foundation
import Observation

/// Guest identities that count as an account (PRD §3.2), so a person's history never splits in
/// two: their web-era or typed-in guest seat and their account are one person, from game 1.
///
/// - `guestIDs`: guests this phone's account claimed (`POST /v1/claims`), and a seat the host typed
///   in that this phone took over ("Is this Sam? · Yes, that's me", design §5.7). They count as
///   the viewer.
/// - `accounts`: who claimed every guest at this account's tables, as the server lists them
///   (`GET /v1/players/me/games` `claims`): a friend's claimed guest counts as the friend's
///   account on this phone too. Replaced on every history pull, so a claim made since shows up.
///
/// Op logs keep the guest seat as it was, so stats map these guests onto the account
/// (`StatsOptions.aliases`, applied app-wide by `.appServices()`).
@Observable
final class ClaimedGuests {
    static let shared = ClaimedGuests()
    static let defaultsKey = "kedro.claimedGuests"
    static let accountsKey = "kedro.guestAccounts"

    private(set) var guestIDs: Set<GuestID>
    private(set) var accounts: [GuestID: PlayerID]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        guestIDs = Set(stored.compactMap(GuestID.init(uuidString:)))
        let pairs = (defaults.dictionary(forKey: Self.accountsKey) as? [String: String]) ?? [:]
        accounts = Dictionary(uniqueKeysWithValues: pairs.compactMap { guest, player in
            guard let guest = GuestID(uuidString: guest), let player = PlayerID(uuidString: player) else { return nil }
            return (guest, player)
        })
    }

    func record(_ ids: some Sequence<GuestID>) {
        let merged = guestIDs.union(ids)
        guard merged != guestIDs else { return }
        guestIDs = merged
        defaults.set(merged.map(\.uuidString).sorted(), forKey: Self.defaultsKey)
    }

    /// The server's claims for every guest at this account's tables (replaces the last list).
    func replaceAccounts(_ claims: [GuestID: PlayerID]) {
        guard claims != accounts else { return }
        accounts = claims
        defaults.set(Dictionary(uniqueKeysWithValues: claims.map { ($0.key.uuidString, $0.value.uuidString) }), forKey: Self.accountsKey)
    }

    /// Forgets other people's claims (signing in as someone else: the next pull lists theirs).
    func resetAccounts() {
        replaceAccounts([:])
    }

    /// The stats aliases for a viewer: their own claimed guests count as them, and every other
    /// claimed guest as the account that claimed it (the server's word wins).
    func aliases(for viewer: PlayerRef?) -> [PlayerRef: PlayerRef] {
        var aliases: [PlayerRef: PlayerRef] = [:]
        if let viewer {
            for guest in guestIDs where PlayerRef.guest(guest) != viewer {
                aliases[.guest(guest)] = viewer
            }
        }
        for (guest, player) in accounts {
            aliases[.guest(guest)] = .player(player)
        }
        return aliases
    }
}
