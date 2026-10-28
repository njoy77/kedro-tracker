import Foundation
import Testing
@testable import Kedro

@Suite("GameOperation JSON (API contract)")
struct OperationCodingTests {
    private func json(_ operation: GameOperation) throws -> [String: Any] {
        let data = try KedroJSON.encoder().encode(operation)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Envelope keys and shapes")
    func envelope() throws {
        let operation = try #require(PreviewData.sampleOperations().first { $0.type == .roundRecorded })
        let object = try json(operation)
        #expect(Set(object.keys) == ["opId", "gameId", "deviceId", "hlc", "actorPlayerId", "type", "payload"])
        #expect(object["opId"] as? String == operation.opId.uuidString.lowercased())
        #expect(object["gameId"] as? String == PreviewData.sampleGameID.uuidString)
        #expect(object["type"] as? String == "RoundRecorded")
        #expect(object["actorPlayerId"] as? String == PreviewData.noah.id.uuidString)
        let hlc = try #require(object["hlc"] as? [String: Any])
        #expect(Set(hlc.keys) == ["wallMs", "counter", "node"])
        #expect((hlc["wallMs"] as? NSNumber)?.int64Value == operation.hlc.wallMs)
        let payload = try #require(object["payload"] as? [String: Any])
        let round = try #require(payload["round"] as? [String: Any])
        let hands = try #require(round["hands"] as? [String: Any])
        #expect(hands[PreviewData.noahSeat.rawValue] as? Int == 9)
        #expect(hands[PreviewData.samSeat.rawValue] as? Int == 15)
        #expect(round["knocker"] as? String == PreviewData.anaSeat.rawValue)
        #expect(PreviewData.samSeat.rawValue.hasPrefix("g:"))
    }

    @Test("A missing actor is an explicit null")
    func nullActor() throws {
        let operation = GameOperation(gameId: GameID(), deviceId: DeviceID(), hlc: HLC(wallMs: 1, node: "n"), actorPlayerId: nil, payload: .gameAbandoned(.init()))
        let data = try KedroJSON.encoder().encode(operation)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"actorPlayerId\":null"))
        #expect(text.contains("\"payload\":{}"))
    }

    @Test("Every sample and history operation round-trips")
    func roundTrip() throws {
        let encoder = KedroJSON.encoder()
        let decoder = KedroJSON.decoder()
        let operations = PreviewData.sampleOperations(throughRound: 5, finished: false, liveKnock: true)
            + PreviewData.sampleOperations()
            + PreviewData.historyOperations
        for operation in operations {
            let decoded = try decoder.decode(GameOperation.self, from: encoder.encode(operation))
            #expect(decoded == operation)
        }
        #expect(Set(operations.map(\.type)).count >= 10)
    }

    @Test("Every payload type round-trips", arguments: OperationType.allCases)
    func payloads(type: OperationType) throws {
        let seat = PreviewData.noahSeat
        let round = PreviewData.sampleRounds[0]
        let payload: OperationPayload = switch type {
        case .gameCreated: .gameCreated(.init(config: GameConfig(tableWord: "Cold Deck", houseVoiceCap: .spicy), host: seat))
        case .gameStarted: .gameStarted(.init(seatOrder: [seat], firstDealer: seat))
        case .playerSeated: .playerSeated(.init(seat: PreviewData.sampleSeats[4]))
        case .seatRemoved: .seatRemoved(.init(seatId: seat))
        case .scorekeeperChanged: .scorekeeperChanged(.init(seatId: seat))
        case .roundRecorded: .roundRecorded(.init(round: round))
        case .roundEdited: .roundEdited(.init(round: round))
        case .roundUndone: .roundUndone(.init(roundNumber: 1))
        case .knockMarked: .knockMarked(.init(roundNumber: 1, knocker: nil))
        case .knockerProposed: .knockerProposed(.init(roundNumber: 1, knocker: seat))
        case .knockerResolved: .knockerResolved(.init(roundNumber: 1, knocker: seat))
        case .handReported: .handReported(.init(roundNumber: 1, seatId: seat, hand: -1, knocked: true))
        case .roundsChanged: .roundsChanged(.init(plannedRounds: 8))
        case .dealerChanged: .dealerChanged(.init(roundNumber: 2, dealer: seat))
        case .tauntSent: .tauntSent(.init(tauntId: UUID(), roundNumber: 1, from: nil, fromName: "Jo", target: .table, content: .custom(text: "hi")))
        case .tauntRetracted: .tauntRetracted(.init(tauntId: UUID(), reason: nil))
        case .reactionAdded: .reactionAdded(.init(roundNumber: 1, seatId: seat, reaction: .salute))
        case .receiptSent: .receiptSent(.init(fromSeat: seat, toSeat: PreviewData.anaSeat, receiptKey: "RC-02"))
        case .tableSpeakerClaimed: .tableSpeakerClaimed(.init(deviceId: DeviceID()))
        case .gameFinished: .gameFinished(.init(reason: .endedEarly, finalRounds: [round]))
        case .gameAbandoned: .gameAbandoned(.init())
        case .gameRestored: .gameRestored(.init())
        }
        #expect(payload.type == type)
        let operation = GameOperation(gameId: GameID(), deviceId: DeviceID(), hlc: HLC(wallMs: 5, counter: 2, node: "node"), actorPlayerId: PlayerID(), payload: payload)
        let decoded = try KedroJSON.decoder().decode(GameOperation.self, from: KedroJSON.encoder().encode(operation))
        #expect(decoded == operation)
        #expect(try json(operation)["type"] as? String == type.rawValue)
    }

    @Test("Avatar, PlayerRef and Handle JSON")
    func smallTypes() throws {
        let encoder = KedroJSON.encoder()
        #expect(String(decoding: try encoder.encode(Avatar.emoji("🦊", colorIndex: 3)), as: UTF8.self) == #"{"colorIndex":3,"emoji":"🦊","kind":"emoji"}"#)
        #expect(String(decoding: try encoder.encode(Avatar.curated(.redKing)), as: UTF8.self) == #"{"id":"redKing","kind":"curated"}"#)
        #expect(String(decoding: try encoder.encode(PreviewData.noah.ref), as: UTF8.self) == #"{"id":"\#(PreviewData.noah.id.uuidString)","kind":"player"}"#)
        #expect(String(decoding: try encoder.encode(Handle(constant: "noah.k")), as: UTF8.self) == #""noah.k""#)
        #expect(throws: DecodingError.self) { try KedroJSON.decoder().decode(Handle.self, from: Data(#""No""#.utf8)) }
    }

    @Test("Unknown operation types fail to decode")
    func unknownType() {
        let text = #"{"opId":"8f14e45f-ceea-467f-a9b0-3a1c4b2d5e6f","gameId":"8f14e45f-ceea-467f-a9b0-3a1c4b2d5e6f","deviceId":"8f14e45f-ceea-467f-a9b0-3a1c4b2d5e6f","hlc":{"wallMs":1,"counter":0,"node":"n"},"actorPlayerId":null,"type":"Nope","payload":{}}"#
        #expect(throws: DecodingError.self) { try KedroJSON.decoder().decode(GameOperation.self, from: Data(text.utf8)) }
    }
}

@Suite("HLC")
struct HLCTests {
    @Test("Ticks are strictly increasing, even when the wall clock stalls or goes back")
    func monotonic() {
        let times = Mutexed([1000, 1000, 999, 1500])
        let clock = HybridLogicalClock(node: "a") { times.next() }
        let stamps = (0..<4).map { _ in clock.tick() }
        #expect(stamps == stamps.sorted())
        #expect(Set(stamps).count == 4)
        #expect(stamps[1] == HLC(wallMs: 1000, counter: 1, node: "a"))
        #expect(stamps[2] == HLC(wallMs: 1000, counter: 2, node: "a"))
        #expect(stamps[3] == HLC(wallMs: 1500, counter: 0, node: "a"))
    }

    @Test("Receiving a remote timestamp from the future orders later events after it")
    func receive() {
        let clock = HybridLogicalClock(node: "a") { 1000 }
        let remote = HLC(wallMs: 5000, counter: 3, node: "b")
        clock.receive(remote)
        let next = clock.tick()
        #expect(next > remote)
        #expect(next.wallMs == 5000)
    }

    @Test("String form round-trips and sorts like the HLC")
    func stringForm() {
        let a = HLC(wallMs: 1_761_700_000_000, counter: 2, node: "8f14e45f-ceea-467f-a9b0-3a1c4b2d5e6f")
        let b = HLC(wallMs: 1_761_700_000_000, counter: 10, node: "1")
        #expect(a.stringValue == "001761700000000-00002-8f14e45f-ceea-467f-a9b0-3a1c4b2d5e6f")
        #expect(HLC(string: a.stringValue) == a)
        #expect((a < b) == (a.stringValue < b.stringValue))
    }
}

/// A thread-safe sequence of canned clock values.
nonisolated final class Mutexed: @unchecked Sendable {
    private var values: [Int64]
    private let lock = NSLock()

    init(_ values: [Int64]) { self.values = values }

    func next() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return values.count > 1 ? values.removeFirst() : values[0]
    }
}

@Suite("Handle")
struct HandleTests {
    @Test("Valid handles are normalized", arguments: [("@Noah", "noah"), (" noah.k ", "noah.k"), ("a_b.9", "a_b.9")])
    func valid(input: String, expected: String) {
        #expect(Handle(input)?.rawValue == expected)
        #expect(Handle(input)?.description == "@" + expected)
    }

    @Test("Invalid handles are rejected", arguments: ["no", "this-has-dashes", "way_too_long_for_a_handle", "émile", "sp ace", ""])
    func invalid(input: String) {
        #expect(Handle(input) == nil)
    }

    @Test("Suggestions from a first name")
    func suggestions() {
        let suggestions = Handle.suggestions(firstName: "Noah", lastInitial: "K").map(\.rawValue)
        #expect(suggestions.first == "noah")
        #expect(suggestions.contains("noah.k"))
        #expect(Handle.suggestions(firstName: "Jo").allSatisfy { Handle.isValid($0.rawValue) })
        #expect(Handle.suggestions(firstName: "Zoë").first?.rawValue == "zoe")
    }
}
