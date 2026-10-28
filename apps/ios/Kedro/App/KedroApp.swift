import SwiftUI

@main
struct KedroApp: App {
    @State private var appModel = AppModel.live()
    @State private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .appEnvironment(appModel, auth: auth)
        }
    }
}
