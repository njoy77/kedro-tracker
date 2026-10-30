import Foundation

/// A guest identity the App Clip played as, waiting to be claimed by the full app (design §5.8,
/// §5.9 #9). Installing Kedro and signing in reads this from the app group and claims the history
/// with `POST /v1/claims {claimToken}`.
nonisolated struct PendingGuestClaim: Codable, Hashable, Sendable {
    /// The guest's `GuestID` (lowercase UUID string): the seat they picked with "That's me".
    var guestID: String
    var displayName: String
    /// Issued by the backend for this guest; nil if the clip couldn't get one (offline).
    var claimToken: String?
    /// Games played as this guest, oldest first (`GameID`s).
    var gameIDs: [String]
    /// The host's name, for "Noah's table" in the app's claim prompt.
    var hostName: String?
    var updatedAt: Date
}

/// Reads and writes `PendingGuestClaim` in the app group. Never logs the token.
nonisolated struct ClaimTokenStore {
    static let key = "claims.pendingGuest"

    let defaults: UserDefaults

    init(defaults: UserDefaults = KedroAppGroup.defaults) {
        self.defaults = defaults
    }

    func pending() -> PendingGuestClaim? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? SharedJSON.decoder().decode(PendingGuestClaim.self, from: data)
    }

    /// Records that this guest played `gameID`, keeping any token already stored. A different
    /// guest replaces the old record only if the old one has no games (a clip is one person).
    func record(guestID: String, displayName: String, gameID: String, hostName: String?, claimToken: String?, now: Date = .now) {
        var claim: PendingGuestClaim
        if let existing = pending(), existing.guestID == guestID {
            claim = existing
            claim.displayName = displayName
            claim.hostName = hostName ?? existing.hostName
            claim.claimToken = claimToken ?? existing.claimToken
        } else if let existing = pending(), !existing.gameIDs.isEmpty {
            // A second guest identity on the same phone: keep the first, which has history
            // (TODO(backend): claim the second from the same device once the first is claimed).
            _ = existing
            return
        } else {
            claim = PendingGuestClaim(guestID: guestID, displayName: displayName, claimToken: claimToken, gameIDs: [], hostName: hostName, updatedAt: now)
        }
        if !claim.gameIDs.contains(gameID) {
            claim.gameIDs.append(gameID)
        }
        claim.updatedAt = now
        save(claim)
    }

    func save(_ claim: PendingGuestClaim) {
        if let data = try? SharedJSON.encoder().encode(claim) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Call after `POST /v1/claims` succeeds.
    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
