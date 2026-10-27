import SwiftUI

@main
struct KedroApp: App {
    @State private var appModel = AppModel()
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(auth)
                .preferredColorScheme(.dark)
        }
    }
}
