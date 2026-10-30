import Foundation
import Synchronization

/// One connection between two phones at a table, carrying `LinkMessage`s. The Network framework
/// (TLS over TCP, peer-to-peer), MultipeerConnectivity (the fallback) and in-memory pairs (tests,
/// previews) all look the same to `TableLink`.
nonisolated protocol LinkChannel: AnyObject, Sendable {
    var id: UUID { get }
    /// Messages from the other phone. Finishes when the connection closes (throws if it failed).
    var messages: AsyncThrowingStream<LinkMessage, any Error> { get }
    func send(_ message: LinkMessage) async throws
    func close()
}

nonisolated enum LinkChannelError: Error, Equatable, Sendable {
    case closed
    case timedOut
}

/// Two channels wired to each other in memory. Every message goes through `LinkFrame` and a
/// `FrameDecoder`, in deliberately small chunks, so tests exercise the real framing.
nonisolated final class InMemoryLinkChannel: LinkChannel {
    let id = UUID()
    let messages: AsyncThrowingStream<LinkMessage, any Error>
    private let continuation: AsyncThrowingStream<LinkMessage, any Error>.Continuation
    private let state = Mutex<State>(State())

    private struct State {
        var peer: InMemoryLinkChannel?
        var decoder = FrameDecoder()
        var isClosed = false
    }

    private init() {
        (messages, continuation) = AsyncThrowingStream.makeStream(of: LinkMessage.self)
    }

    /// A connected pair: what one sends, the other receives.
    static func pair() -> (InMemoryLinkChannel, InMemoryLinkChannel) {
        let a = InMemoryLinkChannel()
        let b = InMemoryLinkChannel()
        a.state.withLock { $0.peer = b }
        b.state.withLock { $0.peer = a }
        return (a, b)
    }

    func send(_ message: LinkMessage) async throws {
        let frame = try LinkFrame.encode(message)
        guard let peer = state.withLock({ $0.isClosed ? nil : $0.peer }) else { throw LinkChannelError.closed }
        // Deliver in 7-byte chunks to exercise reassembly.
        var index = frame.startIndex
        while index < frame.endIndex {
            let end = min(index + 7, frame.endIndex)
            try peer.receive(Data(frame[index..<end]))
            index = end
        }
    }

    private func receive(_ bytes: Data) throws {
        let decoded = try state.withLock { state -> [LinkMessage]? in
            guard !state.isClosed else { return nil }
            return try state.decoder.messages(from: bytes)
        }
        guard let decoded else { throw LinkChannelError.closed }
        for message in decoded { continuation.yield(message) }
    }

    func close() {
        let peer = state.withLock { state -> InMemoryLinkChannel? in
            guard !state.isClosed else { return nil }
            state.isClosed = true
            defer { state.peer = nil }
            return state.peer
        }
        continuation.finish()
        peer?.close()
    }
}
