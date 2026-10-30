import CryptoKit
import Foundation
import Testing
@testable import Kedro

/// A stand-in for the API's attestation signer (apps/api services/link.ts), for tests.
struct TestLinkServer {
    let key = Curve25519.Signing.PrivateKey()

    var publicKey: Data { key.publicKey.rawRepresentation }

    func attestation(player: PlayerID, device: DeviceID, deviceKey: Data, expiresAt: Date = .now.addingTimeInterval(86_400)) throws -> String {
        let body: [String: Any] = [
            "p": player.uuidString.lowercased(), "d": device.uuidString.lowercased(),
            "k": deviceKey.base64URLEncoded, "e": HLC.milliseconds(expiresAt),
        ]
        let payload = try JSONSerialization.data(withJSONObject: body).base64URLEncoded
        let signature = try key.signature(for: Data(payload.utf8)).base64URLEncoded
        return "\(payload).\(signature)"
    }

    /// An identity service for a phone, holding this server's key and an attestation for the person (if an account).
    func identityService(for identity: LocalIdentity) throws -> LinkIdentityService {
        let defaults = try #require(UserDefaults(suiteName: "link-identity-\(UUID().uuidString)"))
        let service = LinkIdentityService(keys: InMemoryLinkDeviceKeyStore(), defaults: defaults)
        service.save(serverKey: publicKey)
        if let player = identity.player?.playerID {
            let attestation = try attestation(player: player, device: identity.deviceID, deviceKey: service.devicePublicKey())
            service.save(attestation: attestation, player: player, device: identity.deviceID, expiresAt: .now.addingTimeInterval(86_400))
        }
        return service
    }
}

@Suite("Table link identity")
struct LinkIdentityTests {
    private func hello(_ identity: LocalIdentity, game: GameID, proof: LinkIdentityProof?) -> LinkHello {
        LinkHello(purpose: .join, game: game, device: identity.deviceID, person: identity.player, displayName: identity.displayName, identity: proof)
    }

    @Test("A signed hello proves the person; a claimed one does not")
    func provesIdentity() throws {
        let server = TestLinkServer()
        let game = GameID()
        let ana = LocalIdentity(deviceID: DeviceID(), player: .player(PlayerID()), displayName: "Ana")
        let anaIdentity = try server.identityService(for: ana)
        let hub = try server.identityService(for: LocalIdentity(deviceID: DeviceID(), player: .player(PlayerID()), displayName: "Noah"))

        let proof = try #require(anaIdentity.proof(game: game, device: ana.deviceID, person: ana.player))
        #expect(hub.verifies(hello(ana, game: game, proof: proof)))
        // No proof: just a claim.
        #expect(!hub.verifies(hello(ana, game: game, proof: nil)))
        // Ana's proof, replayed by another phone or at another table, proves nothing.
        var impostor = ana
        impostor.deviceID = DeviceID()
        #expect(!hub.verifies(hello(impostor, game: game, proof: proof)))
        #expect(!hub.verifies(hello(ana, game: GameID(), proof: proof)))
        // Ana's proof doesn't make someone else Ana.
        var other = ana
        other.player = .player(PlayerID())
        #expect(!hub.verifies(hello(other, game: game, proof: proof)))
        // An attestation from a different server key is worthless.
        let forger = TestLinkServer()
        let forged = try forger.identityService(for: ana)
        let forgedProof = try #require(forged.proof(game: game, device: ana.deviceID, person: ana.player))
        #expect(!hub.verifies(hello(ana, game: game, proof: forgedProof)))
    }

    @Test("The hub admits a seated person only with a verified identity, and never someone blocked")
    func admission() async throws {
        var game = TestGame(players: 3)
        game.setUp()
        let server = TestLinkServer()
        let store = InMemoryGameStore(operations: game.operations)
        let hostIdentity = LocalIdentity(deviceID: game.deviceA, player: game.seats[0].player, displayName: "P0")
        let blockedPerson = PlayerRef.player(PlayerID())
        let link = TableLink(
            store: store, identity: { hostIdentity }, secrets: InMemoryTableSecretStore(),
            networking: InMemoryLinkNetworking(air: InMemoryTableAir()), isFallbackEnabled: { false },
            isPlayedWith: { $0 == blockedPerson }, isBlocked: { $0 == blockedPerson },
            linkIdentity: try server.identityService(for: hostIdentity), timing: .fast
        )
        let state = try await store.gameState(game.gameID)
        let seated = LocalIdentity(deviceID: game.deviceB, player: game.seats[1].player, displayName: "P1")
        let seatedService = try server.identityService(for: seated)
        let signed = hello(seated, game: game.gameID, proof: seatedService.proof(game: game.gameID, device: seated.deviceID, person: seated.player))

        #expect(await link.admission(for: signed, state: state, game: game.gameID) == .admit)
        #expect(await link.admission(for: hello(seated, game: game.gameID, proof: nil), state: state, game: game.gameID) == .ask)
        let blocked = LocalIdentity(deviceID: DeviceID(), player: blockedPerson, displayName: "Jo")
        let blockedService = try server.identityService(for: blocked)
        let blockedHello = hello(blocked, game: game.gameID, proof: blockedService.proof(game: game.gameID, device: blocked.deviceID, person: blocked.player))
        #expect(await link.admission(for: blockedHello, state: state, game: game.gameID) == .refuse)
    }
}
