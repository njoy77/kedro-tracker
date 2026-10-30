import SwiftUI

@main
struct KedroApp: App {
    /// Push needs an app delegate (see `PushAppDelegate` for why UIKit).
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @State private var appModel: AppModel
    @State private var auth: AuthStore
    @State private var network: NetworkServices

    init() {
        let auth = AuthStore()
        let appModel = AppModel.live()
        // Before `AppModel.start()` (RootView's task), so a resumed game uses the real transport.
        _network = State(initialValue: NetworkServices.install(in: appModel, auth: auth))
        TalkServices.shared.configure(auth: auth)
        _auth = State(initialValue: auth)
        _appModel = State(initialValue: appModel)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .appServices()
                .liveGameActivity()
                .environment(network)
                .appEnvironment(appModel, auth: auth)
                .onOpenURL { network.push.handle($0) }
                .task {
                    pushDelegate.service = network.push
                    await network.run()
                }
        }
    }
}
