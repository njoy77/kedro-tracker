#if DEBUG
import Foundation

/// DEBUG only: launch arguments that put the app straight into a known state, for screenshots
/// and quick checks in the Simulator without tapping through onboarding:
///
/// ```
/// xcrun simctl launch booted com.njoy77.kedro -KedroDemo -KedroScreen table
/// ```
///
/// `-KedroDemo` signs in as the test user (Noah), skips onboarding and loads the demo history.
/// `-KedroScreen` then opens one of: `play` (default), `table` (the sample table after Round 5,
/// live), `gameEnd` (the finished sample game), `board`, `profile`, `settings`. From the Table,
/// `kedro://table/<gameID>?action=recordRound` opens the Round sheet.
enum DebugLaunch {
    enum Screen: String {
        case play, table, gameEnd, board, profile, settings
    }

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-KedroDemo") }

    static var screen: Screen {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-KedroScreen"), arguments.indices.contains(index + 1) else { return .play }
        return Screen(rawValue: arguments[index + 1]) ?? .play
    }

    static func run(app: AppModel, auth: AuthStore) async {
        guard isRequested else { return }
        // Let the saved session restore first, or it would sign the test user back out.
        for _ in 0..<50 where auth.state == .loading {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if auth.signedInUser == nil { auth.signInAsTestUser() }
        // The demo's Noah (same face and handle as in the sample games).
        if app.profile == nil { app.profiles.save(PreviewData.noahProfile) }
        app.didSignIn(userID: AuthStore.testUserID, displayName: "Noah")
        app.preferences.hasCompletedOnboarding = true
        let screen = screen
        do {
            // The sample table uses the sample game's ID, so the finished copy stays out of it.
            try await DemoDataSeeder.seed(into: app.store, includeSampleGame: screen != .table)
            switch screen {
            case .table:
                _ = try await app.store.append(PreviewData.sampleOperations(throughRound: 5, finished: false))
                app.startLiveGame(try await app.makeSession(for: PreviewData.sampleGameID), present: true)
            case .gameEnd:
                app.startLiveGame(try await app.makeSession(for: PreviewData.sampleGameID), present: true)
            case .board:
                app.selectedTab = .board
            case .profile:
                app.selectedTab = .you
            case .settings:
                app.navigate(to: .settings, in: .play)
            case .play:
                app.selectedTab = .play
            }
        } catch {
            app.toasts.show(error.localizedDescription)
        }
    }
}
#endif
