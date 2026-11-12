import SwiftUI

/// The four tabs (design §15). Each tab owns a `NavigationStack` that resolves `AppRoute`s.
/// Search is the system search tab (`role: .search`): it sits apart from the other tabs, and
/// selecting it turns the tab bar into the search field. The live game is a `fullScreenCover` that
/// minimizes into the tab bar's bottom accessory.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    /// The Search tab's query. Kept here, above the tab, so it survives switching tabs.
    @State private var searchQuery = ""

    private var stats: StatsModel { .shared(for: app.store) }

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
                    SearchView(query: searchQuery).appRouteDestinations()
                }
                // On the search tab's stack, not the TabView: there it would also put a search
                // field in the other tabs' nav bars (and leave one active after cancelling).
                .searchable(text: $searchQuery, prompt: "Name or @handle")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }
        }
        // Selecting Search activates the field in the tab bar, and its close button goes back to the
        // previous tab. On iOS 27 this is also what gives the search tab its own button beside the
        // bar (UIKit's `automaticallyActivatesSearch`, which makes a search tab prominent).
        .tabViewSearchActivation(.searchTabSelection)
        .tint(.kedroRed)
        .liveGameAccessory(isEnabled: app.liveGame != nil && !app.isTablePresented)
        // Taunt toasts and sounds for the live game, minimized or not (one monitor per game).
        .trashTalk(for: app.liveGame, presentsFeed: false)
        .fullScreenCover(isPresented: $app.isTablePresented) {
            if let session = app.liveGame {
                TableView(session: session)
                    .environment(\.tableInsights, tableInsights(for: session))
                    .environment(\.tauntRendering, .talk)
                    .toastHost(app.toasts)
            }
        }
    }

    /// Stats' titles and game-end progression for the Table (Features/Table/TableInsights.swift).
    private func tableInsights(for session: GameSession) -> TableInsights {
        .stats(
            titles: stats.tableTitles(for: session.state.seats),
            isLoaded: stats.isLoaded,
            store: app.store,
            viewer: app.profile?.identity,
            options: stats.options
        )
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
