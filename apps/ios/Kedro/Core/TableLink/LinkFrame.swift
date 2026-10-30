import Foundation

/// Length-prefixed framing for the table link: `[UInt32 big-endian length][payload]`, where the
/// payload is one `LinkMessage` as JSON (`KedroJSON`). TCP (under TLS) is a byte stream, so the
/// receiver uses `FrameDecoder` to cut it back into messages.
nonisolated enum LinkFrame {
    static let headerSize = 4
    /// A generous ceiling: a full game log is far smaller. Anything larger is a broken or hostile peer.
    static let maxPayloadSize = 4 * 1024 * 1024

    /// Encodes one message as a complete frame.
    static func encode(_ message: LinkMessage) throws -> Data {
        try frame(KedroJSON.encoder().encode(message))
    }

    /// Wraps a payload in a frame.
    static func frame(_ payload: Data) throws -> Data {
        guard payload.count <= maxPayloadSize else { throw FrameError.frameTooLarge(payload.count) }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: headerSize)
        frame.append(payload)
        return frame
    }

    static func decode(_ payload: Data) throws -> LinkMessage {
        try KedroJSON.decoder().decode(LinkMessage.self, from: payload)
    }

    /// Splits a batch of operations so each `operations` frame stays well under the limit.
    static func batches(_ operations: [GameOperation], size: Int = 200) -> [[GameOperation]] {
        stride(from: 0, to: operations.count, by: size).map { Array(operations[$0..<min($0 + size, operations.count)]) }
    }
}

nonisolated enum FrameError: Error, Equatable, Sendable {
    /// The length header announced more than `LinkFrame.maxPayloadSize`.
    case frameTooLarge(Int)
}

/// Reassembles frames from a byte stream that arrives in arbitrary chunks (a frame can be split
/// across reads, and one read can hold several frames).
nonisolated struct FrameDecoder: Sendable {
    private var buffer = Data()

    /// Bytes received but not yet part of a complete frame.
    var bufferedByteCount: Int { buffer.count }

    /// Adds received bytes and returns every payload completed by them, in order.
    /// Throws `FrameError.frameTooLarge` on an oversized header (close the connection).
    mutating func append(_ bytes: Data) throws -> [Data] {
        buffer.append(bytes)
        var payloads: [Data] = []
        while buffer.count >= LinkFrame.headerSize {
            let start = buffer.startIndex
            let length = buffer[start..<start + LinkFrame.headerSize].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= LinkFrame.maxPayloadSize else { throw FrameError.frameTooLarge(length) }
            let frameEnd = start + LinkFrame.headerSize + length
            guard buffer.endIndex >= frameEnd else { break }
            payloads.append(Data(buffer[(start + LinkFrame.headerSize)..<frameEnd]))
            buffer = Data(buffer[frameEnd...])
        }
        return payloads
    }

    /// Like `append`, decoding each payload. A payload that doesn't decode (a message from a newer
    /// version) is skipped rather than ending the connection.
    mutating func messages(from bytes: Data) throws -> [LinkMessage] {
        try append(bytes).compactMap { try? LinkFrame.decode($0) }
    }
}
