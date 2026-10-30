import Foundation

/// Finds tables nearby and advertises this phone's table (design §5.2–§5.4). The Networking
/// agent implements it in Core/Nearby (Bonjour `_kedro-table._tcp`, Nearby Interaction);
/// `NoNearbyTables` is the stand-in.
protocol TableDiscovery: AnyObject, Sendable {
    /// The tables currently visible, closest first. Yields whenever the set changes.
    func nearbyTables() -> AsyncStream<[NearbyTable]>

    /// Starts advertising a table this phone hosts or sits at.
    func advertise(_ table: AdvertisedTable) async

    func stopAdvertising() async
}

/// A table seen nearby (the Table card, design §5.3).
nonisolated struct NearbyTable: Hashable, Sendable, Identifiable {
    var id: GameID
    var host: PlayerSummary
    var tableWord: String
    /// Meters, from Nearby Interaction (UWB). nil when unavailable.
    var distance: Double?
    var seatedPlayers: [PlayerSummary]
    var guestCount: Int
    /// You've played with the host (or were added by them): Sit Down seats you immediately;
    /// otherwise it's Ask to Sit.
    var isPlayedWith: Bool
    /// Rounds saved so far (0 in the lobby). After Round 1, latecomers can only Watch.
    var roundsPlayed: Int

    /// Under ~3 m: "At your table". Farther: "Other tables nearby".
    static let atYourTableDistance = 3.0

    var isAtYourTable: Bool { (distance ?? .infinity) < Self.atYourTableDistance }
    var seatsAreLocked: Bool { roundsPlayed > 0 }
}

/// What this phone advertises (the TXT record carries these; design §5.2).
nonisolated struct AdvertisedTable: Hashable, Sendable {
    var gameID: GameID
    var hostName: String
    var tableWord: String
    var seatCount: Int
    var roundsPlayed: Int
}

/// Sees no tables, advertises nothing.
final class NoNearbyTables: TableDiscovery {
    func nearbyTables() -> AsyncStream<[NearbyTable]> {
        AsyncStream { continuation in
            continuation.yield([])
        }
    }

    func advertise(_ table: AdvertisedTable) async {}

    func stopAdvertising() async {}
}
