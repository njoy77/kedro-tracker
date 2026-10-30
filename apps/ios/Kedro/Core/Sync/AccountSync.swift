import Foundation
import OSLog

/// The real `AccountSyncing` (design §5.1, §5.9 #9): keeps the server's player row in step with
/// the phone's profile and claims guest history once the person has an account.
///
/// Claims come from three places, all redeemed with `POST /v1/claims {claimToken}`:
/// - the guest profile's own token ("Play as a guest", then sign in),
/// - codes typed into "Got a claim code?" (`PendingClaims`),
/// - seats the App Clip played as (`ClaimTokenStore` in the app group).
///
/// Each is removed once the server accepts it (or refuses it for good); network failures keep it
/// for the next sign-in.
final class AccountSync: AccountSyncing {
    private let api: APIClient
    private let clipClaims: ClaimTokenStore
    private let defaults: UserDefaults
    private let onClaimed: @MainActor (Int) async -> Void
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Account")

    /// - Parameter onClaimed: Runs after games were claimed (pull them again, refresh widgets).
    init(
        api: APIClient,
        clipClaims: ClaimTokenStore = ClaimTokenStore(),
        defaults: UserDefaults = .standard,
        onClaimed: @escaping @MainActor (Int) async -> Void = { _ in }
    ) {
        self.api = api
        self.clipClaims = clipClaims
        self.defaults = defaults
        self.onClaimed = onClaimed
    }

    func uploadProfile(_ profile: LocalProfile) async -> ProfileUploadResult {
        guard !profile.isGuest, await api.hasAccount() else { return .notSent }
        let handle = profile.handle ?? Handle.suggestions(firstName: profile.displayName).first
        guard let handle else { return .notSent }
        do {
            let avatar = try await Self.uploadableAvatar(profile.avatar, api: api)
            _ = try await api.updateMe(PlayerUpdate(displayName: profile.displayName, handle: handle, avatar: avatar, titleID: profile.titleID))
            return .saved
        } catch APIError.badStatus(409) {
            return .handleTaken
        } catch {
            log.info("Profile not sent: \(String(describing: error), privacy: .public)")
            return .notSent
        }
    }

    func claimGuestHistory(guestToken: String?) async -> Int {
        guard await api.hasAccount() else { return 0 }
        var claimed = 0
        if let guestToken, let games = await redeem(guestToken) {
            claimed += games
        }
        for code in PendingClaims.all(defaults: defaults) {
            guard let games = await redeem(code) else { continue }
            PendingClaims.remove(code, defaults: defaults)
            claimed += games
        }
        for claim in clipClaims.redeemable() {
            guard let token = claim.claimToken, let games = await redeem(token) else { continue }
            clipClaims.remove(guestID: claim.guestID)
            claimed += games
        }
        if claimed > 0 { await onClaimed(claimed) }
        return claimed
    }

    /// The games claimed, 0 when the token was refused for good (already claimed, unknown), or
    /// nil when it should be tried again later.
    private func redeem(_ token: String) async -> Int? {
        do {
            return try await api.claim(token: token).gamesClaimed
        } catch let error as APIError where error.isRetryable || error == .notSignedIn {
            return nil
        } catch {
            log.info("Claim refused: \(String(describing: error), privacy: .public)")
            return 0
        }
    }

    /// The avatar to send. A photo still on this phone (`file://`) can't be sent until photo
    /// upload exists, so the server keeps whatever it has, or gets a starter emoji.
    private static func uploadableAvatar(_ avatar: Avatar?, api: APIClient) async throws -> Avatar {
        switch avatar {
        case .photo(let url) where url.isFileURL:
            // TODO(backend): photo upload endpoint; then upload and send the remote URL here.
            if let current = try? await api.me().avatar { return current }
            return .randomStarter()
        case .some(let avatar):
            return avatar
        case nil:
            return .randomStarter()
        }
    }
}
