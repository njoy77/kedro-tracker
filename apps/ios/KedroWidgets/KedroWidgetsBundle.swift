import SwiftUI
import WidgetKit

/// The KedroWidgets extension: the live game's Live Activity and the three home/Lock Screen
/// widgets (design §13.2, §13.3).
@main
struct KedroWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LiveGameActivityWidget()
        StandingWidget()
        RivalryWidget()
        NextBadgeWidget()
    }
}
