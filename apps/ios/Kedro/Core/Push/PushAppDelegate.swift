import Foundation
import OSLog
import UIKit
import UserNotifications

/// The app delegate Kedro needs for push, installed with `@UIApplicationDelegateAdaptor`.
///
/// UIKit because SwiftUI has no way to receive the APNs device token
/// (`didRegisterForRemoteNotificationsWithDeviceToken` exists only on `UIApplicationDelegate`),
/// and the notification-center delegate must be set before launch finishes so a tap that
/// launched the app isn't lost. Everything else lives in `PushService`.
///
/// Events that arrive before `service` is set (a cold launch from a notification) are kept and
/// replayed when it is.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    var service: PushService? {
        didSet { replay() }
    }

    private var pendingToken: Data?
    private var pendingInvites: [TableInvite] = []
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Push")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if let service {
            Task { await service.didRegister(deviceToken: deviceToken) }
        } else {
            pendingToken = deviceToken
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        log.info("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    fileprivate func opened(_ invite: TableInvite) {
        if let service {
            service.didOpen(invite)
        } else {
            pendingInvites.append(invite)
        }
    }

    fileprivate var presentation: UNNotificationPresentationOptions {
        service?.foregroundPresentation ?? [.banner, .list]
    }

    private func replay() {
        guard let service else { return }
        if let token = pendingToken {
            pendingToken = nil
            Task { await service.didRegister(deviceToken: token) }
        }
        for invite in pendingInvites { service.didOpen(invite) }
        pendingInvites = []
    }
}

extension PushAppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let invite = TableInvite(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { opened(invite) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { presentation }
    }
}
