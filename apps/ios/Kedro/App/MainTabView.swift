import SwiftUI

/// The four tabs (design §15). Each tab owns a `NavigationStack` that resolves `AppRoute`s.
/// The live game is a `fullScreenCover` that minimizes into the tab bar's bottom accessory.
struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        TabView(selection: $app.selectedTab) {
            Tab("Play", systemImage: "suit.spade.fill", value: AppTab.play) {
                NavigationStack(path: $app.playPath) {
                    PlayView().appRouteDestinations()
                }
            }
            Tab("Board", systemImage: "list.number", value: AppTab.board) {
                NavigationStack(path: $app.boardPath) {
                    LeaderboardView().appRouteDestinations()
                }
            }
            Tab("You", systemImage: "person.crop.circle", value: AppTab.you) {
                NavigationStack(path: $app.youPath) {
                    YouTab().appRouteDestinations()
                }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $app.searchPath) {
                    SearchView().appRouteDestinations()
                }
            }
        }
        .tint(.kedroRed)
        .liveGameAccessory(isEnabled: app.liveGame != nil && !app.isTablePresented)
        .fullScreenCover(isPresented: $app.isTablePresented) {
            if let session = app.liveGame {
                TableView(session: session)
                    .toastHost(app.toasts)
            }
        }
    }
}

/// The You tab: your profile, or a nudge if this phone has no profile yet.
private struct YouTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let me = app.profile?.identity {
            ProfileView(player: me)
        } else {
            ContentUnavailableView("No Profile Yet", systemImage: "person.crop.circle", description: Text("Play a game to start your record."))
        }
    }
}

private extension View {
    /// The mini bar in the tab bar accessory while a game is minimized. `isEnabled` needs
    /// iOS 26.1; on 26.0 the accessory is added and removed instead.
    @ViewBuilder
    func liveGameAccessory(isEnabled: Bool) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isEnabled) { LiveGameMiniBar() }
        } else if isEnabled {
            tabViewBottomAccessory { LiveGameMiniBar() }
        } else {
            self
        }
    }
}

#Preview("Tabs") {
    MainTabView()
        .previewEnvironment()
}

#Preview("Tabs with a live game") {
    MainTabView()
        .previewEnvironment(AppModel.preview(liveGame: true))
}
