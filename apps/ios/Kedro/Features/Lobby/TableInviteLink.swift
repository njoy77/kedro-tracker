import CryptoKit
import Foundation

/// A link into a table (design §5.8, §5.9):
/// - `https://playkedro.com/t/{gameID}?k={token}`: the rotating QR / AirDrop invite. Opens the app if
///   installed (universal link), otherwise the App Clip.
/// - `https://playkedro.com/s/{gameID}?host={name}&word={word}`: "saved you a seat" (§5.5, N-01). The
///   push's tap target; carries the host and table word so the Table card can show before the
///   game has synced.
///
/// `kedro://t/…` and `kedro://s/…` are accepted too.
nonisolated struct TableInviteLink: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case table = "t"
        case savedSeat = "s"
    }

    static let webHost = KedroLink.webHost
    static let scheme = "kedro"

    var kind: Kind
    var gameID: GameID
    /// The rotating token (QR invites).
    var token: String?
    var hostName: String?
    var tableWord: String?

    init(kind: Kind = .table, gameID: GameID, token: String? = nil, hostName: String? = nil, tableWord: String? = nil) {
        self.kind = kind
        self.gameID = gameID
        self.token = token
        self.hostName = hostName
        self.tableWord = tableWord
    }

    /// Parses a Kedro table link; nil for anything else.
    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var parts = components.path.split(separator: "/").map(String.init)
        switch components.scheme?.lowercased() {
        case "https" where components.host?.lowercased() == Self.webHost:
            break
        case Self.scheme:
            // kedro://t/<id>: the first segment arrives as the host.
            if let host = components.host { parts.insert(host, at: 0) }
        default:
            return nil
        }
        guard parts.count == 2, let kind = Kind(rawValue: parts[0]), let id = GameID(uuidString: parts[1]) else { return nil }
        let query = Dictionary((components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
        self.init(kind: kind, gameID: id, token: query["k"], hostName: query["host"], tableWord: query["word"])
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.webHost
        components.path = "/\(kind.rawValue)/\(gameID.uuidString)"
        var items: [URLQueryItem] = []
        if let token { items.append(URLQueryItem(name: "k", value: token)) }
        if let hostName { items.append(URLQueryItem(name: "host", value: hostName)) }
        if let tableWord { items.append(URLQueryItem(name: "word", value: tableWord)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url ?? URL(filePath: "/")
    }
}

/// The invite token that rotates every 60 s (J-12: "screenshots won't work"). An HMAC of the game
/// and the current minute under a per-table secret, so only the host can mint or check one.
/// The current and previous windows are accepted to cover a scan right at the rollover.
nonisolated struct RotatingTableToken: Sendable {
    static let period: TimeInterval = 60

    let gameID: GameID
    let secret: SymmetricKey

    init(gameID: GameID, secret: SymmetricKey = SymmetricKey(size: .bits256)) {
        self.gameID = gameID
        self.secret = secret
    }

    static func window(at date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 / period).rounded(.down))
    }

    /// When the token shown at `date` stops being current.
    static func nextRotation(after date: Date) -> Date {
        Date(timeIntervalSince1970: Double(window(at: date) + 1) * period)
    }

    func token(at date: Date) -> String {
        token(window: Self.window(at: date))
    }

    func isValid(_ token: String, at date: Date) -> Bool {
        let window = Self.window(at: date)
        return token == self.token(window: window) || token == self.token(window: window - 1)
    }

    func link(at date: Date) -> TableInviteLink {
        TableInviteLink(kind: .table, gameID: gameID, token: token(at: date))
    }

    private func token(window: Int64) -> String {
        let message = Data("\(gameID.uuidString)|\(window)".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: secret)
        return Data(mac).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .prefix(16)
            .description
    }
}

/// Keeps one invite secret per table for the life of the app, so closing and reopening the lobby
/// (or the QR sheet) doesn't invalidate a code someone is about to scan.
enum TableTokenVault {
    private static var tokens: [GameID: RotatingTableToken] = [:]

    static func token(for game: GameID) -> RotatingTableToken {
        if let token = tokens[game] { return token }
        let token = RotatingTableToken(gameID: game)
        tokens[game] = token
        return token
    }
}
