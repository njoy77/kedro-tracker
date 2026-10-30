import SwiftUI

/// The tabs (design §15): Play, Board, You, and Search (the `.search` role).
enum AppTab: Hashable {
    case play, board, you, search
}

/// Value-based navigation destinations shared by every tab. Push with
/// `NavigationLink(value: AppRoute.profile(ref))` or `app.navigate(to:)`.
///
/// Each tab's `NavigationStack` is created by `MainTabView` and resolves these with
/// `.appRouteDestinations()`, so feature root views must not create their own `NavigationStack`.
/// A sheet that hosts route destinations (Rules, the Knock Calculator, Learn) wraps them in its
/// own `NavigationStack` and applies `.appRouteDestinations()` itself.
///
/// Every push on a tab's stack must be an `AppRoute`: the tabs bind a typed `[AppRoute]` path, so
/// a `NavigationLink(value:)` of any other type can't join it and silently never pushes. Add a case
/// here instead of a feature-specific route type.
enum AppRoute: Hashable {
    /// A player's profile (PRD §5.1; guests only in game context).
    case profile(PlayerRef)
    /// Head-to-head between two people (design §12.3).
    case headToHead(PlayerRef, PlayerRef)
    case badges(PlayerRef)
    case hallOfShame
    case wrapped(year: Int)
    /// A stored game's history (read-only once finished).
    case gameHistory(GameID)
    case settings
    /// Settings → the profile editor.
    case editProfile
    case learn
    /// Learn → the 2-minute cards ending in the knock-gamble quiz.
    case learnCards
    /// Learn → the Score a Round drill.
    case scoreRoundDrill
    case rules
    /// The Knock Calculator, optionally prefilled from a round (design §13.1).
    case knockCalculator(Round?)
}

extension View {
    /// Resolves `AppRoute` values. Applied by `MainTabView` inside each tab's stack.
    func appRouteDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            AppRouteDestination(route: route)
        }
    }
}

/// The screen for a route.
struct AppRouteDestination: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .profile(let player): ProfileView(player: player)
        case let .headToHead(a, b): HeadToHeadView(a: a, b: b)
        case .badges(let player): BadgesView(player: player)
        case .hallOfShame: HallOfShameView()
        case .wrapped(let year): WrappedView(year: year)
        case .gameHistory(let game): GameRecordView(gameID: game)
        case .settings: SettingsView()
        case .editProfile: ProfileEditView()
        case .learn: LearnView()
        case .learnCards: LearnCardsView()
        case .scoreRoundDrill: ScoreRoundDrill()
        case .rules: RulesSheet()
        case .knockCalculator(let round): KnockCalculatorView(prefill: round)
        }
    }
}

#Preview {
    NavigationStack {
        AppRouteDestination(route: .knockCalculator(PreviewData.sampleRounds[4]))
    }
    .previewEnvironment()
}
