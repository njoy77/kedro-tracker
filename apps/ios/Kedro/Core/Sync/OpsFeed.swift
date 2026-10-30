import Foundation
import OSLog
import Supabase

/// New operations on the backend for one game, as they're stored (Supabase Realtime on
/// `public.ops`, filtered by `game_id`). `BackendSync` treats each event as a doorbell: it uses
/// the decoded operations when the row decodes, and pulls `GET /v1/games/:id/ops?after=` when not.
protocol OpsFeed: AnyObject, Sendable {
    /// Events until the consumer's task is cancelled.
    func events(for game: GameID) -> AsyncStream<OpsFeedEvent>
}

nonisolated enum OpsFeedEvent: Hashable, Sendable {
    /// Operations decoded straight from the inserted rows.
    case operations([GameOperation])
    /// Something changed, but the row couldn't be decoded: pull to catch up.
    case changed
    /// The subscription (re)connected: pull, since events may have been missed while it was down.
    case subscribed
}

/// A feed that never rings (previews, tests, signed-out phones).
final class SilentOpsFeed: OpsFeed {
    func events(for game: GameID) -> AsyncStream<OpsFeedEvent> {
        AsyncStream { _ in }
    }
}

/// Supabase Realtime `postgres_changes` (inserts) on `public.ops` for one game. RLS applies, so
/// only seated players receive anything. Uses the AuthStore's client, which keeps Realtime's
/// access token current.
final class SupabaseOpsFeed: OpsFeed {
    private let client: () -> SupabaseClient?
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Sync")

    /// - Parameter client: The AuthStore's Supabase client (read when a subscription starts).
    init(client: @escaping () -> SupabaseClient? = { SupabaseAccessToken.client }) {
        self.client = client
    }

    func events(for game: GameID) -> AsyncStream<OpsFeedEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: OpsFeedEvent.self, bufferingPolicy: .bufferingNewest(64))
        guard let client = client() else {
            continuation.finish()
            return stream
        }
        let log = log
        let task = Task {
            let channel = client.channel("ops:\(game.uuidString)")
            let inserts = channel.postgresChange(
                InsertAction.self, schema: "public", table: "ops",
                filter: .eq("game_id", value: game.uuidString)
            )
            do {
                try await channel.subscribeWithError()
                continuation.yield(.subscribed)
                for await insert in inserts {
                    if let operation = OpsRow.operation(from: insert.record) {
                        continuation.yield(.operations([operation]))
                    } else {
                        continuation.yield(.changed)
                    }
                }
            } catch is CancellationError {
            } catch {
                log.info("Realtime ended for a game: \(error.localizedDescription, privacy: .public)")
            }
            await client.removeChannel(channel)
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}

/// A row of `public.ops` as Realtime delivers it, converted to the contract's `Operation`.
/// Column names are the backend's (`supabase/migrations`); if they ever drift, decoding fails
/// and the feed falls back to a pull, so nothing is lost.
nonisolated enum OpsRow {
    static func operation(from record: [String: AnyJSON]) -> GameOperation? {
        guard
            let opID = record["op_id"]?.stringValue,
            let gameID = record["game_id"]?.stringValue,
            let deviceID = record["device_id"]?.stringValue,
            let hlcString = record["hlc"]?.stringValue,
            let hlc = HLC(string: hlcString),
            let type = record["type"]?.stringValue,
            let payload = record["payload"]
        else { return nil }
        let actor: AnyJSON = record["actor"].flatMap { $0.stringValue.map(AnyJSON.string) } ?? .null
        let contract: [String: AnyJSON] = [
            "opId": .string(opID),
            "gameId": .string(gameID),
            "deviceId": .string(deviceID),
            "hlc": .object(["wallMs": .integer(Int(hlc.wallMs)), "counter": .integer(hlc.counter), "node": .string(hlc.node)]),
            "actorPlayerId": actor,
            "type": .string(type),
            "payload": payload,
        ]
        guard let data = try? JSONEncoder().encode(contract) else { return nil }
        return try? KedroJSON.decoder().decode(GameOperation.self, from: data)
    }
}
