import CryptoKit
import Foundation
import OSLog
import Security

/// Proof of who a phone's person is, carried in `LinkHello.identity` (design §5.3).
///
/// A hub admits a phone without Ask to Sit when its person is already seated or is someone the
/// hub's owner has played with, so that claim has to be checked: `hello.person` alone is just
/// what the connecting phone says, and seated players' IDs are visible to anyone nearby.
///
/// - The server signs an **attestation** (`POST /v1/link/attestations`, Ed25519): this account
///   owns this device's link key, until an expiry a week out.
/// - The phone signs each hello with that device key, over the game, the device, the person and
///   the time, so an attestation seen by one hub can't be replayed at another table or later.
///
/// Hubs check both offline with the server's public key (`GET /link/key`, cached), so it works
/// at a table with no internet. Guests (no account) can't prove an identity; they get in with a
/// membership proof, the QR code, or Ask to Sit.
nonisolated struct LinkIdentityProof: Hashable, Sendable, Codable {
    /// `<payload>.<signature>` from the server (base64url both).
    var attestation: String
    var signedAtMs: Int64
    /// The device key's signature over `LinkIdentityProof.message(...)`.
    var signature: Data

    static func message(game: GameID, device: DeviceID, person: PlayerID, signedAtMs: Int64) -> Data {
        Data("kedro.hello|\(game.uuidString)|\(device.uuidString)|\(person.uuidString)|\(signedAtMs)".utf8)
    }

    /// How far a hello's time may be from the hub's clock.
    static let maxClockSkewMs: Int64 = 10 * 60 * 1000

    /// The decoded attestation payload (`{p, d, k, e}`), if the server signature checks out.
    struct Attested: Hashable, Sendable {
        var player: PlayerID
        var device: DeviceID
        var deviceKey: Data
        var expiresAtMs: Int64
    }

    static func verifiedAttestation(_ attestation: String, serverKey: Data) -> Attested? {
        let parts = attestation.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let signature = Data(base64URLEncoded: String(parts[1])),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: serverKey),
              key.isValidSignature(signature, for: Data(parts[0].utf8)),
              let json = Data(base64URLEncoded: String(parts[0])),
              let body = try? JSONDecoder().decode(Payload.self, from: json),
              let player = PlayerID(uuidString: body.p), let device = DeviceID(uuidString: body.d),
              let deviceKey = Data(base64URLEncoded: body.k)
        else { return nil }
        return Attested(player: player, device: device, deviceKey: deviceKey, expiresAtMs: body.e)
    }

    private struct Payload: Decodable {
        var p: String
        var d: String
        var k: String
        var e: Int64
    }

    /// Whether this proof shows that the phone `device` really is `person`, for `game`, now.
    func proves(_ person: PlayerID, device: DeviceID, game: GameID, serverKey: Data, nowMs: Int64) -> Bool {
        guard let attested = Self.verifiedAttestation(attestation, serverKey: serverKey),
              attested.player == person, attested.device == device, attested.expiresAtMs > nowMs,
              abs(nowMs - signedAtMs) <= Self.maxClockSkewMs,
              let deviceKey = try? Curve25519.Signing.PublicKey(rawRepresentation: attested.deviceKey)
        else { return false }
        return deviceKey.isValidSignature(signature, for: Self.message(game: game, device: device, person: person, signedAtMs: signedAtMs))
    }
}

/// This phone's link identity: the device key (Keychain), the server's attestation for the
/// signed-in account and the server's public key (both cached), refreshed whenever online.
@Observable
final class LinkIdentityService {
    @ObservationIgnored private let keys: any LinkDeviceKeyStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "LinkIdentity")

    private static let attestationKey = "kedro.link.attestation"
    private static let serverKeyKey = "kedro.link.serverKey"

    /// Refresh the attestation when it has less than this left.
    static let refreshMargin: TimeInterval = 2 * 24 * 60 * 60

    init(keys: any LinkDeviceKeyStore = KeychainLinkDeviceKeyStore(), defaults: UserDefaults = .standard) {
        self.keys = keys
        self.defaults = defaults
    }

    /// The server's attestation key, as last fetched.
    var serverKey: Data? { defaults.data(forKey: Self.serverKeyKey) }

    private var cached: CachedAttestation? {
        get { defaults.data(forKey: Self.attestationKey).flatMap { try? JSONDecoder().decode(CachedAttestation.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.attestationKey) }
    }

    /// Fetches the server key and (for an account) a fresh attestation when the cached one is
    /// missing, for another account or device, or close to expiring. Failures keep what's cached.
    func refresh(api: APIClient, player: PlayerID?, device: DeviceID, now: Date = .now) async {
        do {
            if let key = try await api.linkKey() { save(serverKey: key) }
        } catch {
            log.info("Link key not fetched: \(String(describing: error), privacy: .public)")
        }
        guard let player, await api.hasAccount() else { return }
        if let cached, cached.player == player, cached.device == device,
           cached.expiresAt.timeIntervalSince(now) > Self.refreshMargin { return }
        do {
            let key = try keys.signingKey()
            let response = try await api.linkAttestation(device: device, publicKey: key.publicKey.rawRepresentation)
            save(attestation: response.attestation, player: player, device: device, expiresAt: response.expiresAt)
        } catch {
            log.info("Link attestation not refreshed: \(String(describing: error), privacy: .public)")
        }
    }

    func save(serverKey: Data) {
        defaults.set(serverKey, forKey: Self.serverKeyKey)
    }

    func save(attestation: String, player: PlayerID, device: DeviceID, expiresAt: Date) {
        cached = CachedAttestation(player: player, device: device, attestation: attestation, expiresAt: expiresAt)
    }

    /// The device's public link key (what the server attests).
    func devicePublicKey() throws -> Data {
        try keys.signingKey().publicKey.rawRepresentation
    }

    /// A proof for a hello, or nil without a current attestation for this person and device.
    func proof(game: GameID, device: DeviceID, person: PlayerRef?, now: Date = .now) -> LinkIdentityProof? {
        guard let player = person?.playerID, let cached, cached.player == player, cached.device == device,
              cached.expiresAt > now, let key = try? keys.signingKey() else { return nil }
        let signedAtMs = HLC.milliseconds(now)
        let message = LinkIdentityProof.message(game: game, device: device, person: player, signedAtMs: signedAtMs)
        guard let signature = try? key.signature(for: message) else { return nil }
        return LinkIdentityProof(attestation: cached.attestation, signedAtMs: signedAtMs, signature: signature)
    }

    /// Whether a hello's identity proof checks out against the cached server key.
    func verifies(_ hello: LinkHello, now: Date = .now) -> Bool {
        guard let player = hello.person?.playerID, let proof = hello.identity, let serverKey else { return false }
        return proof.proves(player, device: hello.device, game: hello.game, serverKey: serverKey, nowMs: HLC.milliseconds(now))
    }

    private struct CachedAttestation: Codable {
        var player: PlayerID
        var device: DeviceID
        var attestation: String
        var expiresAt: Date
    }
}

// MARK: - Device key

/// Where the device's link signing key lives.
protocol LinkDeviceKeyStore: AnyObject {
    /// The device key, made (and saved) on first use.
    func signingKey() throws -> Curve25519.Signing.PrivateKey
}

/// The device key in the Keychain (this device only; available after first unlock, so a locked
/// phone at the table can still rejoin).
final class KeychainLinkDeviceKeyStore: LinkDeviceKeyStore {
    private let service = "com.njoy77.kedro.link-key"
    private let account = "device"

    func signingKey() throws -> Curve25519.Signing.PrivateKey {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: data)
        }
        let key = Curve25519.Signing.PrivateKey()
        var add = baseQuery
        add[kSecValueData as String] = key.rawRepresentation
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
        return key
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}

/// A device key in memory (tests and previews).
final class InMemoryLinkDeviceKeyStore: LinkDeviceKeyStore {
    private var key: Curve25519.Signing.PrivateKey?

    func signingKey() throws -> Curve25519.Signing.PrivateKey {
        if let key { return key }
        let new = Curve25519.Signing.PrivateKey()
        key = new
        return new
    }
}
