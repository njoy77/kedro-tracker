import Foundation

/// A guest seat the App Clip played as, waiting to be claimed by the full app (design §5.8,
/// §5.9 #9). Installing Kedro and signing in reads these from the app group and claims each one
/// with `POST /v1/claims {claimToken}` → `{guestId, gamesClaimed}`.
///
/// JSON (sorted keys, ISO 8601): `{"claimToken":"…","displayName":"Sam","gameIDs":["…"],
/// "guestID":"…","hostName":"Noah","updatedAt":"2026-10-30T21:40:00Z"}`; `claimToken` and
/// `hostName` are omitted when nil.
nonisolated struct PendingGuestClaim: Codable, Hashable, Sendable, Identifiable {
    /// The guest's `GuestID` (lowercase UUID string): the seat they picked with "That's me".
    var guestID: String
    var displayName: String
    /// Issued by the backend for this guest; nil while the clip couldn't get one (offline).
    var claimToken: String?
    /// Games played as this guest, oldest first (`GameID`s, lowercase UUID strings).
    var gameIDs: [String]
    /// The host's name, for "Noah's table" in the app's claim prompt.
    var hostName: String?
    var updatedAt: Date

    var id: String { guestID }

    /// Only claims with a token can be redeemed.
    var isRedeemable: Bool { !(claimToken ?? "").isEmpty }
}

/// Reads and writes the pending guest claims in the app group. A clip is one person, but hosts
/// create a new guest for them at every table, so there can be several guest IDs to claim.
/// Never logs the tokens.
nonisolated struct ClaimTokenStore: @unchecked Sendable {
    // @unchecked: `UserDefaults` is thread-safe but not marked Sendable.

    static let key = "claims.pendingGuests"

    let defaults: UserDefaults

    init(defaults: UserDefaults = KedroAppGroup.defaults) {
        self.defaults = defaults
    }

    /// Every pending claim, oldest first.
    func pending() -> [PendingGuestClaim] {
        guard let data = defaults.data(forKey: Self.key),
              let claims = try? SharedJSON.decoder().decode([PendingGuestClaim].self, from: data)
        else { return [] }
        return claims
    }

    /// The claims the app can redeem now.
    func redeemable() -> [PendingGuestClaim] { pending().filter(\.isRedeemable) }

    /// Records that this guest played `gameID`. Keeps a token already stored when `claimToken`
    /// is nil (a later offline launch must not erase it).
    func record(guestID: String, displayName: String, gameID: String, hostName: String?, claimToken: String?, now: Date = .now) {
        var claims = pending()
        if let index = claims.firstIndex(where: { $0.guestID == guestID }) {
            claims[index].displayName = displayName
            claims[index].hostName = hostName ?? claims[index].hostName
            claims[index].claimToken = claimToken ?? claims[index].claimToken
            if !claims[index].gameIDs.contains(gameID) {
                claims[index].gameIDs.append(gameID)
            }
            claims[index].updatedAt = now
        } else {
            claims.append(PendingGuestClaim(
                guestID: guestID, displayName: displayName, claimToken: claimToken,
                gameIDs: [gameID], hostName: hostName, updatedAt: now
            ))
        }
        save(claims)
    }

    /// Call after `POST /v1/claims` succeeds for this guest.
    func remove(guestID: String) {
        save(pending().filter { $0.guestID != guestID })
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }

    private func save(_ claims: [PendingGuestClaim]) {
        guard !claims.isEmpty else {
            clear()
            return
        }
        if let data = try? SharedJSON.encoder().encode(claims) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
