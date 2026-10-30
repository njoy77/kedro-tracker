import CryptoKit
import Foundation
import Testing
@testable import Kedro

@Suite("Table link framing")
struct LinkFrameTests {
    private func sampleOperations() -> [GameOperation] {
        var game = TestGame(players: 4)
        game.setUp()
        game.record([3, 12, 7, 20], knocker: 0)
        game.record([5, 2, 9, 11], knocker: 1)
        return game.operations
    }

    @Test("An operations batch survives encode → frame → decode unchanged")
    func roundTrip() throws {
        let operations = sampleOperations()
        let frame = try LinkFrame.encode(.operations(operations))

        let length = frame.prefix(LinkFrame.headerSize).reduce(0) { ($0 << 8) | Int($1) }
        #expect(length == frame.count - LinkFrame.headerSize)

        var decoder = FrameDecoder()
        let messages = try decoder.messages(from: frame)
        #expect(messages == [.operations(operations)])
        #expect(decoder.bufferedByteCount == 0)
    }

    @Test("Frames split across reads, and several in one read, are reassembled in order")
    func reassembly() throws {
        let operations = sampleOperations()
        let messages: [LinkMessage] = [
            .ping(7),
            .operations(operations),
            .inventory(game: operations[0].gameId, opIDs: operations.map(\.opId)),
            .goodbye,
        ]
        let stream = try messages.reduce(into: Data()) { $0.append(try LinkFrame.encode($1)) }

        for chunkSize in [1, 3, 7, 64, 1000, stream.count] {
            var decoder = FrameDecoder()
            var received: [LinkMessage] = []
            var index = stream.startIndex
            while index < stream.endIndex {
                let end = min(index + chunkSize, stream.endIndex)
                received += try decoder.messages(from: Data(stream[index..<end]))
                index = end
            }
            #expect(received == messages, "chunk size \(chunkSize)")
            #expect(decoder.bufferedByteCount == 0)
        }
    }

    @Test("A partial frame waits for the rest")
    func partialFrame() throws {
        let frame = try LinkFrame.encode(.pong(42))
        var decoder = FrameDecoder()
        #expect(try decoder.messages(from: frame.prefix(frame.count - 1)).isEmpty)
        #expect(decoder.bufferedByteCount == frame.count - 1)
        #expect(try decoder.messages(from: frame.suffix(1)) == [.pong(42)])
    }

    @Test("An oversized length header is rejected")
    func oversized() {
        var header = UInt32(LinkFrame.maxPayloadSize + 1).bigEndian
        let frame = Data(bytes: &header, count: 4)
        var decoder = FrameDecoder()
        #expect(throws: FrameError.frameTooLarge(LinkFrame.maxPayloadSize + 1)) {
            try decoder.append(frame)
        }
    }

    @Test("A payload from a newer version is skipped, not fatal")
    func unknownMessage() throws {
        let unknown = try LinkFrame.frame(Data(#"{"fromTheFuture":{}}"#.utf8))
        let known = try LinkFrame.encode(.ping(1))
        var decoder = FrameDecoder()
        #expect(try decoder.messages(from: unknown + known) == [.ping(1)])
    }

    @Test("Large logs are split into bounded batches")
    func batches() {
        let operations = Array(repeating: sampleOperations(), count: 60).flatMap { $0 }
        let batches = LinkFrame.batches(operations, size: 200)
        #expect(batches.allSatisfy { $0.count <= 200 })
        #expect(batches.flatMap { $0 } == operations)
    }

    @Test("In-memory channels deliver through real framing")
    @MainActor
    func inMemoryChannel() async throws {
        let (a, b) = InMemoryLinkChannel.pair()
        let operations = sampleOperations()
        try await a.send(.operations(operations))
        a.close()
        var received: [LinkMessage] = []
        for try await message in b.messages { received.append(message) }
        #expect(received == [.operations(operations)])
    }
}

@Suite("Table advertisement and keys")
struct TableAdvertisementTests {
    @Test("The TXT record carries the table and parses back")
    func txtRoundTrip() throws {
        let ana = PlayerID()
        let ad = TableAdvertisement(
            game: GameID(), tableWord: "Cold Deck", hostName: "Maya", hostPlayer: PlayerID(),
            hostHandle: Handle("maya"), hostAvatar: .emoji("🃏", colorIndex: 3), seatCount: 5, guestCount: 1,
            roundsPlayed: 2, isStarted: true,
            seated: [.init(id: ana, displayName: "Ana", handle: Handle("ana.b"))],
            hub: DeviceID(), hubSeatOrder: 1
        )
        let txt = ad.txtDictionary
        #expect(txt["t"] == ad.game.uuidString)
        #expect(txt["w"] == "Cold Deck")
        #expect(txt["n"] == "5")
        #expect(txt["r"] == "2")
        #expect(txt.values.allSatisfy { $0.utf8.count <= 255 })

        // The host's player ID is never advertised (anyone nearby could claim to be them).
        #expect(txt["hp"] == nil)
        let parsed = try #require(TableAdvertisement(txt: txt))
        var expected = ad
        expected.hostPlayer = nil
        #expect(parsed == expected)
    }

    @Test("Records that aren't Kedro tables are ignored")
    func foreignRecord() {
        #expect(TableAdvertisement(txt: ["v": "1", "t": "nope"]) == nil)
        #expect(TableAdvertisement(txt: [:]) == nil)
    }

    @Test("Hub rank: lowest seat first, watchers last, ties by device")
    func hubRank() {
        let a = DeviceID(), b = DeviceID()
        #expect(HubRank(seatOrder: 0, device: a) < HubRank(seatOrder: 1, device: b))
        #expect(HubRank(seatOrder: 4, device: a) < HubRank(seatOrder: nil, device: b))
        let (low, high) = a.uuidString < b.uuidString ? (a, b) : (b, a)
        #expect(HubRank(seatOrder: 2, device: low) < HubRank(seatOrder: 2, device: high))
    }

    @Test("The PSK is per table and stable")
    func presharedKey() {
        let game = GameID()
        let first = TableKey.preSharedKey(for: game).withUnsafeBytes { Data($0) }
        let again = TableKey.preSharedKey(for: game).withUnsafeBytes { Data($0) }
        let other = TableKey.preSharedKey(for: GameID()).withUnsafeBytes { Data($0) }
        #expect(first == again)
        #expect(first != other)
        #expect(first.count == 32)
    }

    @Test("Membership proofs and invite codes verify only with the table secret")
    func proofs() {
        let game = GameID(), device = DeviceID()
        let secret = TableKey.newTableSecret()
        let proof = TableKey.membershipProof(secret: secret, game: game, device: device)
        #expect(TableKey.isValidProof(proof, secret: secret, game: game, device: device))
        #expect(!TableKey.isValidProof(proof, secret: TableKey.newTableSecret(), game: game, device: device))
        #expect(!TableKey.isValidProof(proof, secret: secret, game: game, device: DeviceID()))

        let now = Date(timeIntervalSince1970: 1_761_700_000)
        let code = TableKey.inviteCode(secret: secret, game: game, at: now)
        #expect(TableKey.isValidInviteCode(code, secret: secret, game: game, at: now.addingTimeInterval(59)))
        #expect(!TableKey.isValidInviteCode(code, secret: secret, game: game, at: now.addingTimeInterval(181)))
        #expect(!TableKey.isValidInviteCode(code, secret: TableKey.newTableSecret(), game: game, at: now))
    }
}
