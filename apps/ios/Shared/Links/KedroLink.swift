import Foundation

/// The links Kedro understands, shared by the app, the widgets and the App Clip.
///
/// - `https://kedro.app/t/{gameID}?k={token}`: the Invite with QR / AirDrop link (design §5.8).
///   Opens the app if installed (applinks), the App Clip if not (appclips). `k` rotates every 60 s.
/// - `kedro://table/{gameID}?action=recordRound`: the Live Activity and its buttons.
/// - `kedro://widget/{kind}`: a home screen widget tap.
nonisolated enum KedroLink: Hashable, Sendable {
    case invite(gameID: UUID, token: String?)
    case table(gameID: UUID, action: LiveActivityAction)
    case widget(kind: String)

    static let webHost = "kedro.app"
    static let scheme = "kedro"

    init?(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        let path = url.pathComponents.filter { $0 != "/" }

        switch url.scheme?.lowercased() {
        case "https", "http":
            guard url.host()?.lowercased() == Self.webHost, path.count >= 2, path[0] == "t",
                  let id = UUID(uuidString: path[1])
            else { return nil }
            let token = query.first { $0.name == "k" }?.value.flatMap { $0.isEmpty ? nil : $0 }
            self = .invite(gameID: id, token: token)
        case Self.scheme:
            switch url.host()?.lowercased() {
            case "table":
                guard let first = path.first, let id = UUID(uuidString: first) else { return nil }
                let action = query.first { $0.name == "action" }?.value.flatMap(LiveActivityAction.init(rawValue:))
                self = .table(gameID: id, action: action ?? .openTable)
            case "widget":
                guard let kind = path.first else { return nil }
                self = .widget(kind: kind)
            default:
                return nil
            }
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        switch self {
        case .invite(let gameID, let token):
            components.scheme = "https"
            components.host = Self.webHost
            components.path = "/t/\(gameID.uuidString.lowercased())"
            if let token { components.queryItems = [URLQueryItem(name: "k", value: token)] }
        case .table(let gameID, let action):
            components.scheme = Self.scheme
            components.host = "table"
            components.path = "/\(gameID.uuidString.lowercased())"
            if action != .openTable { components.queryItems = [URLQueryItem(name: "action", value: action.rawValue)] }
        case .widget(let kind):
            components.scheme = Self.scheme
            components.host = "widget"
            components.path = "/\(kind)"
        }
        // Every component above is valid, so this can't fail; the fallback keeps it total.
        return components.url ?? URL(filePath: "/")
    }
}
