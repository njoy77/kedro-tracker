import Foundation

/// A way into a specific table that arrived from outside the app: the "saved you a seat" push
/// (design §5.5, N-01), the QR/AirDrop link (`https://playkedro.com/t/{gameID}?k={code}`, §5.8), or
/// the nearby alert (N-07). The Play tab shows it as the Table card with **Sit Down** focused.
nonisolated struct TableInvite: Hashable, Sendable, Identifiable {
    nonisolated enum Source: String, Hashable, Sendable {
        /// "Maya saved you a seat at Cold Deck." The host already seated you.
        case savedSeat
        /// The rotating QR code or an AirDrop of the same link.
        case link
        /// "Maya started a table nearby." (opt-in Bluetooth alert)
        case nearbyAlert
    }

    var gameID: GameID
    var source: Source
    var hostName: String?
    var tableWord: String?
    /// The rotating invite code from the QR link (`TableKey.inviteCode`): admits without Ask to Sit.
    var inviteCode: String?

    var id: GameID { gameID }

    static let linkHost = KedroLink.webHost
    static let urlScheme = "kedro"

    // MARK: Links

    /// Parses `https://playkedro.com/t/{gameID}?k={code}` or `kedro://t/{gameID}?k={code}`.
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var segments = components.path.split(separator: "/").map(String.init)
        switch components.scheme?.lowercased() {
        case "https" where components.host?.lowercased() == Self.linkHost:
            break
        case Self.urlScheme:
            // kedro://t/{id}: the host is the first segment.
            if let host = components.host { segments.insert(host, at: 0) }
        default:
            return nil
        }
        guard segments.count == 2, segments[0] == "t", let game = GameID(uuidString: segments[1]) else { return nil }
        gameID = game
        source = .link
        inviteCode = components.queryItems?.first { $0.name == "k" }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The link a QR code or AirDrop carries.
    static func link(for game: GameID, inviteCode: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = linkHost
        components.path = "/t/\(game.uuidString.lowercased())"
        components.queryItems = [URLQueryItem(name: "k", value: inviteCode)]
        return components.url ?? URL(filePath: "/")
    }

    // MARK: Notifications

    /// The `kedro` dictionary in a push or local notification's `userInfo`:
    /// `{"kind":"seat","gameId":"…","host":"Maya","word":"Cold Deck"}` (`kind` is `seat` for
    /// N-01 and `nearby` for N-07).
    static let userInfoKey = "kedro"

    init?(userInfo: [AnyHashable: Any]) {
        guard let info = userInfo[Self.userInfoKey] as? [String: Any],
              let gameString = info["gameId"] as? String, let game = GameID(uuidString: gameString)
        else { return nil }
        switch info["kind"] as? String {
        case "seat": source = .savedSeat
        case "nearby": source = .nearbyAlert
        default: return nil
        }
        gameID = game
        hostName = info["host"] as? String
        tableWord = info["word"] as? String
        inviteCode = nil
    }

    init(gameID: GameID, source: Source, hostName: String? = nil, tableWord: String? = nil, inviteCode: String? = nil) {
        self.gameID = gameID
        self.source = source
        self.hostName = hostName
        self.tableWord = tableWord
        self.inviteCode = inviteCode
    }

    /// `userInfo` for a local notification that opens this invite.
    var userInfo: [String: [String: String]] {
        var info = ["gameId": gameID.uuidString, "kind": source == .nearbyAlert ? "nearby" : "seat"]
        info["host"] = hostName
        info["word"] = tableWord
        return [Self.userInfoKey: info]
    }
}
