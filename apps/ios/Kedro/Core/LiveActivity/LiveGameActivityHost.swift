import SwiftUI

extension View {
    /// Runs the system surfaces for this phone: the live game's Live Activity (design §13.2), its
    /// App Intent buttons, `kedro://` links from the Live Activity and widgets, and the widget
    /// freeze during live games (§13.3).
    ///
    /// Apply once at the root, inside `.appEnvironment(_:auth:)`. Puts `LiveActivityController`
    /// and `WidgetSnapshotPublisher` in the environment.
    func liveGameActivity() -> some View {
        modifier(LiveGameActivityHost())
    }
}

private struct LiveGameActivityHost: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = LiveActivityController()
    @State private var widgets = WidgetSnapshotPublisher()

    private var liveGameID: GameID? { app.liveGame?.gameID }
    private var isPlaying: Bool { app.liveGame?.state.status == .active }

    func body(content: Content) -> some View {
        content
            .environment(controller)
            .environment(widgets)
            .task {
                controller.installActionHandler()
                await controller.observePushToStartTokens()
            }
            .task(id: liveGameID) {
                if let session = app.liveGame {
                    let preferences = app.preferences
                    await controller.follow(session) { preferences.effectiveLanguageLevel }
                } else {
                    await controller.endOrphansAfterGracePeriod()
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                controller.isAppActive = phase == .active
            }
            .onChange(of: isPlaying, initial: true) { _, playing in
                widgets.isFrozen = playing
            }
            .onChange(of: controller.pendingAction) { _, request in
                guard let request else { return }
                route(request)
            }
            .onOpenURL { url in
                open(url)
            }
    }

    /// A Live Activity button or tap: bring up the Table. The Table takes the action itself
    /// (`takePendingAction(for:)`) to open the Round sheet or Report Your Hand.
    private func route(_ request: LiveActivityActionRequest) {
        guard let liveGameID, GameID(uuidString: request.gameID) == liveGameID else {
            controller.dropPendingAction()
            return
        }
        app.presentTable()
        if request.action == .openTable {
            controller.dropPendingAction()
        }
    }

    private func open(_ url: URL) {
        switch KedroLink(url: url) {
        case .table(let gameID, let action):
            controller.receive(LiveActivityActionRequest(action: action, gameID: gameID.uuidString.lowercased(), requestedAt: .now))
        case .widget(let kind):
            openWidget(kind)
        case .invite, nil:
            // Invite links (applinks) belong to the lobby's join flow.
            break
        }
    }

    private func openWidget(_ kind: String) {
        guard let me = app.profile?.identity else { return }
        switch kind {
        case KedroWidgetKind.standing:
            app.selectedTab = .board
        case KedroWidgetKind.nextBadge:
            app.navigate(to: .badges(me), in: .you)
        case KedroWidgetKind.rivalry:
            if let rival = widgets.current?.rivalry?.rivalID.flatMap(SeatID.init(rawValue:)) {
                app.navigate(to: .headToHead(me, rival.playerRef), in: .you)
            } else {
                app.selectedTab = .you
            }
        default:
            app.selectedTab = .you
        }
    }
}

#Preview {
    Text(verbatim: "Live Activity host")
        .liveGameActivity()
        .previewEnvironment(.preview(liveGame: true))
}
