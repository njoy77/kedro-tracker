import SwiftUI

enum AppTab: Hashable {
    case games, leaderboard, players
}

struct MainTabView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        TabView(selection: $appModel.selectedTab) {
            Tab("Games", systemImage: "suit.spade.fill", value: .games) {
                GamesView()
            }
            Tab("Leaderboard", systemImage: "trophy.fill", value: .leaderboard) {
                LeaderboardView()
            }
            Tab("Players", systemImage: "person.2.fill", value: .players) {
                PlayersView()
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppModel())
        .environment(AuthStore())
}
