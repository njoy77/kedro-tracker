import CryptoKit
import Foundation

/// One-time value that ties an Apple identity token to a single sign-in attempt.
///
/// Apple receives the SHA-256 hash in the authorization request and embeds it in the identity token.
/// Supabase receives the raw value, hashes it, and checks that the two match.
nonisolated struct AppleSignInNonce: Sendable, Equatable {
    let raw: String

    var hashed: String { Self.sha256(raw) }

    init(raw: String = Self.random()) {
        self.raw = raw
    }

    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset[Int.random(in: charset.indices, using: &generator)] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
