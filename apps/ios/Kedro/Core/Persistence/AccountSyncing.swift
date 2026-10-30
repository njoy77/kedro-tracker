import Foundation

/// The account work that needs the backend (design §5.1, §5.9): uploading the profile and
/// claiming guest history. Networking implements it (`AccountSync` in Core/Sync) and installs it
/// as `AppModel.account`; previews and tests leave it nil, which keeps everything on the phone.
protocol AccountSyncing: AnyObject, Sendable {
    /// `PUT /v1/players/me` with the profile's name, handle, avatar and title.
    func uploadProfile(_ profile: LocalProfile) async -> ProfileUploadResult

    /// Claims every guest history this phone holds for the signed-in account: the guest
    /// profile's own token, codes typed into "Got a claim code?", and App Clip seats. Returns
    /// the number of games claimed.
    func claimGuestHistory(guestToken: String?) async -> Int
}

/// What happened to a profile upload.
nonisolated enum ProfileUploadResult: Hashable, Sendable {
    case saved
    /// 409: someone took the handle in the meantime. Ask for another one.
    case handleTaken
    /// Signed out, offline or the server failed; the profile stays on the phone and is sent again
    /// on the next sign-in or edit.
    case notSent
}
