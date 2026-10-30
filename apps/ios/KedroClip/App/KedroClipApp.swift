import SwiftUI

/// The Kedro App Clip (design §5.8): opened from the table's rotating QR or an AirDrop of
/// `https://playkedro.com/t/{gameID}?k={token}` on an iPhone without Kedro.
@main
struct KedroClipApp: App {
    @State private var model = ClipModel()

    var body: some Scene {
        WindowGroup {
            ClipRootView()
                .environment(model)
                // App Clip invocations (QR, App Clip Code, Safari banner, Messages) arrive as a
                // browsing-web user activity; a plain URL open covers the rest.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    model.open(activity.webpageURL)
                }
                .onOpenURL { url in
                    model.open(url)
                }
        }
    }
}
