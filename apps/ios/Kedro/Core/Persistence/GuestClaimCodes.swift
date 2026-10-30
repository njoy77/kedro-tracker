import Foundation
import Security

/// Claim codes for guests this phone added by name (PRD §3.2, design §5.9 row 9).
///
/// When the host adds "Sam" as a guest, the seat carries the SHA-256 of a new random code
/// (`Seat.claimTokenHash`; the server records the first hash it sees for a guest), and the code
/// itself stays on the host's phone. Game end then offers "Send Sam their claim code" by AirDrop
/// or text; Sam redeems it under "Got a claim code?" once they have an account, and the history
/// moves to them. Codes are secrets: they live in the Keychain, never in logs or the op log.
protocol GuestClaimCodeStoring: AnyObject {
    func code(for guest: GuestID) -> String?
    func save(_ code: String, for guest: GuestID)
}

extension GuestClaimCodeStoring {
    /// The guest's code, making (and saving) one the first time.
    func codeCreatingIfNeeded(for guest: GuestID) -> String {
        if let existing = code(for: guest) { return existing }
        let code = GuestClaimCodes.newCode()
        save(code, for: guest)
        return code
    }
}

nonisolated enum GuestClaimCodes {
    /// 24 random bytes, base64url: what `POST /v1/claims` accepts (16–256 characters).
    static func newCode() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // SecRandomCopyBytes doesn't fail in practice; fall back to the system generator.
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<24).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes).base64URLEncoded
    }

    /// The text sent to the guest (AirDrop, Messages): the code and where to put it.
    static func message(name: String, code: String) -> String {
        "\(name), your Kedro games are waiting. Get Kedro, sign in, and enter this under Got a claim code?: \(code)"
    }
}

/// Codes in the Keychain (this device only).
final class KeychainGuestClaimCodes: GuestClaimCodeStoring {
    static let shared = KeychainGuestClaimCodes()

    private let service = "com.njoy77.kedro.guest-claim"

    func code(for guest: GuestID) -> String? {
        var query = baseQuery(guest)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ code: String, for guest: GuestID) {
        let query = baseQuery(guest)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(code.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    private func baseQuery(_ guest: GuestID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: guest.uuidString]
    }
}

/// Codes in memory (tests and previews).
final class InMemoryGuestClaimCodes: GuestClaimCodeStoring {
    private var codes: [GuestID: String] = [:]

    func code(for guest: GuestID) -> String? { codes[guest] }
    func save(_ code: String, for guest: GuestID) { codes[guest] = code }
}
