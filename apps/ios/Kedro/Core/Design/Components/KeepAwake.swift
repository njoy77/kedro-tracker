import SwiftUI
import UIKit

extension View {
    /// Keeps the screen from sleeping while `active` and this view is on screen (PRD §4.4: the
    /// Table and display mode).
    func keepsScreenAwake(_ active: Bool = true) -> some View {
        modifier(KeepAwakeModifier(active: active))
    }
}

private struct KeepAwakeModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { IdleTimer.update(disabled: active) }
            .onChange(of: active) { _, isActive in IdleTimer.update(disabled: isActive) }
            .onDisappear { IdleTimer.update(disabled: false) }
    }
}

/// UIKit: SwiftUI has no API to stop the screen from auto-locking, so this sets the one
/// `UIApplication.isIdleTimerDisabled` property (design §15, the app's only UIKit).
private enum IdleTimer {
    static func update(disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
    }
}
