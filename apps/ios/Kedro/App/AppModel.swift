import Observation

/// App-wide state shared through the SwiftUI environment.
@Observable
final class AppModel {
    var selectedTab: AppTab = .games
    let api: APIClient

    init(api: APIClient = APIClient(baseURL: AppConfig.apiBaseURL)) {
        self.api = api
    }
}
