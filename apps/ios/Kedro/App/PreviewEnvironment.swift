import SwiftUI

extension View {
    /// Injects everything a feature view reads from the environment, for `#Preview`s:
    /// `AppModel` (in-memory demo data, Noah's profile), its `AppPreferences` and `ToastCenter`,
    /// and an `AuthStore`.
    ///
    /// ```swift
    /// #Preview { PlayView().previewEnvironment() }
    /// #Preview { PlayView().previewEnvironment(AppModel.preview(liveGame: true)) }
    /// ```
    func previewEnvironment(_ model: AppModel = .preview()) -> some View {
        self
            .environment(model)
            .environment(model.preferences)
            .environment(model.toasts)
            .environment(AuthStore())
            .toastHost(model.toasts)
    }

    /// Injects the app's environment objects (used by `KedroApp` and previews).
    func appEnvironment(_ model: AppModel, auth: AuthStore) -> some View {
        self
            .environment(model)
            .environment(model.preferences)
            .environment(model.toasts)
            .environment(auth)
    }
}
