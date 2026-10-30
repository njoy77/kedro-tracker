import CryptoKit
import Foundation
import Security

/// Keys for the table link (design §5.2), in two layers:
///
/// 1. **TLS-PSK from the table token.** The token is derived from the game ID, which every phone
///    near the table can read from the Bonjour TXT record (anyone nearby may Ask to Sit, so the
///    first contact can't need a secret). It keeps the stream private from non-Kedro devices and
///    binds each connection to one table.
/// 2. **Membership from the table secret.** 32 random bytes the first hub makes and hands to every
///    admitted phone in `welcome` (also carried by the QR/AirDrop link and the "saved you a seat"
///    push as `k`). It is never advertised. A phone proves it was admitted with
///    `membershipProof`, so a future hub (after failover) re-admits it without asking.
///
/// Operations only flow to and from members; strangers stay at the door until a seated phone lets
/// them in.
nonisolated enum TableKey {
    static let pskIdentity = Data("kedro-table-v1".utf8)

    /// The table token for a game: public, stable across hubs.
    static func tableToken(for game: GameID) -> Data {
        let digest = SHA256.hash(data: Data("kedro.table-token.v1|\(game.uuidString)".utf8))
        return Data(digest)
    }

    /// The TLS pre-shared key derived from the table token.
    static func preSharedKey(for game: GameID) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: tableToken(for: game)),
            salt: Data("kedro.table-link".utf8),
            info: Data("tls-psk".utf8),
            outputByteCount: 32
        )
    }

    /// A new table secret (the hub makes one per game).
    static func newTableSecret() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// HMAC over the game and device, keyed by the table secret.
    static func membershipProof(secret: Data, game: GameID, device: DeviceID) -> Data {
        let message = Data("kedro.member|\(game.uuidString)|\(device.uuidString)".utf8)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
    }

    static func isValidProof(_ proof: Data, secret: Data, game: GameID, device: DeviceID) -> Bool {
        let message = Data("kedro.member|\(game.uuidString)|\(device.uuidString)".utf8)
        return HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: message, using: SymmetricKey(data: secret))
    }

    /// The key the rotating invite codes are made with: an HMAC of the table secret, so it can be
    /// registered with the server (`PUT /v1/games/:gameId/invite-key`) for the server to check codes
    /// (App Clip sessions, a phone seating itself) without ever holding the secret, which would let
    /// it forge membership proofs.
    static func inviteKey(secret: Data, game: GameID) -> Data {
        let message = Data("kedro.invite-key|\(game.uuidString)".utf8)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
    }

    /// The rotating invite code for the QR link (`https://playkedro.com/t/{gameID}?k={code}`, design
    /// §5.8): changes every 60 s. `isValidInviteCode` accepts the current and previous window.
    /// The server computes the same code from the registered `inviteKey` (apps/api services/invites.ts).
    static func inviteCode(secret: Data, game: GameID, at date: Date = .now) -> String {
        inviteCode(secret: secret, game: game, window: Int64(date.timeIntervalSince1970) / 60)
    }

    static func isValidInviteCode(_ code: String, secret: Data, game: GameID, at date: Date = .now) -> Bool {
        let window = Int64(date.timeIntervalSince1970) / 60
        return [window, window - 1].contains { inviteCode(secret: secret, game: game, window: $0) == code }
    }

    private static func inviteCode(secret: Data, game: GameID, window: Int64) -> String {
        let message = Data("kedro.invite|\(game.uuidString)|\(window)".utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: inviteKey(secret: secret, game: game)))
        return Data(mac.prefix(12)).base64URLEncoded
    }
}

nonisolated extension Data {
    /// RFC 4648 base64url without padding (for URLs and push payloads).
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

// MARK: - Table secrets

/// Where this phone keeps the table secret of each game it was admitted to.
protocol TableSecretStore: AnyObject {
    func secret(for game: GameID) -> Data?
    func save(_ secret: Data, for game: GameID)
}

extension TableSecretStore {
    /// The game's secret, making (and saving) one if this phone is the first hub.
    func secretCreatingIfNeeded(for game: GameID) -> Data {
        if let existing = secret(for: game) { return existing }
        let secret = TableKey.newTableSecret()
        save(secret, for: game)
        return secret
    }
}

/// Table secrets in the Keychain (this device only, available after first unlock so the link
/// keeps working with the screen locked).
final class KeychainTableSecretStore: TableSecretStore {
    private let service = "com.njoy77.kedro.table-secret"

    func secret(for game: GameID) -> Data? {
        var query = baseQuery(game)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func save(_ secret: Data, for game: GameID) {
        let query = baseQuery(game)
        let attributes: [String: Any] = [
            kSecValueData as String: secret,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    private func baseQuery(_ game: GameID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: game.uuidString,
        ]
    }
}

/// Table secrets in memory (tests and previews).
final class InMemoryTableSecretStore: TableSecretStore {
    private var secrets: [GameID: Data] = [:]

    func secret(for game: GameID) -> Data? { secrets[game] }
    func save(_ secret: Data, for game: GameID) { secrets[game] = secret }
}
