import SwiftUI

extension View {
    /// The app-wide links between features that no single screen owns (applied once at the root,
    /// inside `.appEnvironment(_:auth:)` and `.liveGameActivity()`):
    ///
    /// - Stats follow the store for the app's lifetime, with blocked people excluded (Talk's
    ///   moderation) so boards, the Hall of Shame, Wrapped and rivals hide them.
    /// - The widgets get a fresh snapshot whenever finished games change (`WidgetSnapshotPublisher`
    ///   holds it while a game is live).
    /// - Settings → Sounds previews play through Talk's sound player.
    func appServices() -> some View {
        modifier(AppServicesHost())
    }
}

private struct AppServicesHost: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(WidgetSnapshotPublisher.self) private var widgets: WidgetSnapshotPublisher?
    @State private var talk = TalkServices.shared
    @State private var publishedGames: Int?

    private var stats: StatsModel { .shared(for: app.store) }

    func body(content: Content) -> some View {
        content
            .environment(\.soundPreview, SoundPreviewAction { TalkServices.shared.sound.preview($0) })
            .task(id: app.profile?.identity) {
                await stats.follow(app.store, viewer: app.profile?.identity)
            }
            .onChange(of: talk.moderation.blocked, initial: true) { _, blocked in
                guard stats.options.excluded != blocked else { return }
                stats.options.excluded = blocked
                Task { await stats.load(from: app.store, viewer: app.profile?.identity) }
            }
            .onChange(of: WidgetKey(games: stats.snapshot.games.count, level: app.preferences.effectiveLanguageLevel, profile: app.profile)) { _, key in
                publishWidgets(gameCount: key.games)
            }
    }

    private struct WidgetKey: Equatable {
        var games: Int
        var level: LanguageLevel
        var profile: LocalProfile?
    }

    private func publishWidgets(gameCount: Int) {
        guard stats.isLoaded, let widgets, let profile = app.profile else { return }
        let reason: WidgetSnapshotPublisher.Reason = gameCount > (publishedGames ?? gameCount) ? .gameFinished : .claim
        publishedGames = gameCount
        let snapshot = stats.snapshot.widgetSnapshot(
            for: profile.identity, name: profile.displayName, avatar: profile.avatar, voice: app.voice
        )
        widgets.publish(snapshot, reason: reason)
    }
}

#Preview {
    Text(verbatim: "App services")
        .appServices()
        .liveGameActivity()
        .previewEnvironment()
}
