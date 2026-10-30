import Foundation
import Observation
import OSLog
import UIKit
import UserNotifications

/// Notifications (design §13.4): permission in context, APNs registration, token upload to
/// `POST /v1/push/tokens`, and turning a tapped notification or an opened link into a
/// `TableInvite` for the Play tab's Table card.
///
/// Wiring: `PushAppDelegate` (an `@UIApplicationDelegateAdaptor`) forwards the APNs token and
/// notification taps here; `.onOpenURL` forwards links with `handle(_:)`.
@Observable
final class PushService {
    /// The invite the Play tab should show as the Table card, Sit Down focused. Set by a tapped
    /// "saved you a seat" push, a nearby alert, or an opened QR/AirDrop link; clear it with
    /// `consumeInvite()` once shown.
    private(set) var pendingInvite: TableInvite?
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let center: UNUserNotificationCenter
    @ObservationIgnored private let defaults: UserDefaults
    /// Fetches an invited game's log so the Table card has something to show (`BackendSync.pull`).
    @ObservationIgnored var prefetch: (GameID) async -> Void = { _ in }
    /// Whether this phone is seated at a live table: no banners then (design §13.4).
    @ObservationIgnored var isAtLiveTable: () -> Bool = { false }
    @ObservationIgnored private var deviceToken: String?
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "Push")

    private enum Key {
        static let uploadedToken = "kedro.push.uploadedToken"
    }

    init(api: APIClient, center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.api = api
        self.center = center
        self.defaults = defaults
    }

    // MARK: Permission and registration

    /// Reads the current permission (call at launch; never prompts).
    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
        if authorization == .authorized || authorization == .provisional {
            register()
        }
    }

    /// Asks for permission. Call only in context, after the one-line primer (design §5.1).
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Registers with APNs. UIKit: SwiftUI has no API for remote-notification registration, and
    /// the token can only arrive through the app delegate.
    func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// The APNs token arrived (from `PushAppDelegate`).
    func didRegister(deviceToken data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        await uploadToken()
    }

    /// Uploads the APNs token if it hasn't been for this account (call again after sign-in).
    func uploadToken() async {
        guard let token = deviceToken, await api.hasAccount() else { return }
        guard defaults.string(forKey: Key.uploadedToken) != token else { return }
        do {
            try await api.registerPushToken(PushTokenRequest(token: token, kind: .apns))
            defaults.set(token, forKey: Key.uploadedToken)
        } catch {
            log.info("Push token upload failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Signing in as someone else: the token must be uploaded again for the new account.
    func accountChanged() async {
        defaults.removeObject(forKey: Key.uploadedToken)
        await uploadToken()
    }

    /// A Live Activity push token (platform's Live Activity reports it here).
    func registerLiveActivityToken(_ data: Data, for game: GameID) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        do {
            try await api.registerPushToken(PushTokenRequest(token: token, kind: .liveactivity, gameId: game))
        } catch {
            log.info("Live Activity token upload failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Invites

    /// A tapped notification (from `PushAppDelegate`).
    func didOpen(_ invite: TableInvite) {
        show(invite)
    }

    /// A universal link or `kedro://` URL. Returns whether it was a Kedro table link.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let invite = TableInvite(url: url) else { return false }
        show(invite)
        return true
    }

    func consumeInvite() {
        pendingInvite = nil
    }

    private func show(_ invite: TableInvite) {
        pendingInvite = invite
        Task { await prefetch(invite.gameID) }
    }

    // MARK: Local notifications

    /// Posts a local notification (the nearby alert, N-07). Not time-sensitive, no sound.
    func postLocal(id: String, body: String, invite: TableInvite) async {
        let content = UNMutableNotificationContent()
        content.body = body
        content.userInfo = invite.userInfo
        content.interruptionLevel = .active
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        } catch {
            log.info("Couldn't post a notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// How a notification shows while Kedro is open: never on a phone seated at a live table.
    var foregroundPresentation: UNNotificationPresentationOptions {
        isAtLiveTable() ? [] : [.banner, .list]
    }
}
