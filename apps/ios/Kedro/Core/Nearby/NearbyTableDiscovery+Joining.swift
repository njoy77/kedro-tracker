import Foundation

// The lobby's joining contracts (Features/Play/TableJoiner.swift) on the real discovery, backed
// by the `TableLink`: Ask to Sit (J-02) and QR invite codes.
//
// Ask to Sit has no operation: a stranger's phone joins the table's link without a membership
// proof, so the hub holds the connection and every seated phone sees a `SeatRequest`. The lobby
// shows J-02 with "Let {name} In", which seats the person (a `PlayerSeated` with their phone's
// device ID); seeing that seat in the log admits the waiting connection, and the stranger's
// phone receives the table's operations, its own seat included.

extension NearbyTableDiscovery: SeatRequesting {
    func requestSeat(_ seat: Seat, at game: GameID) async throws {
        // Joining without proof is the request; the hub answers `pending` and relays it.
        link.join(game)
    }

    func seatRequests(for game: GameID) -> AsyncStream<Seat> {
        let (stream, continuation) = AsyncStream.makeStream(of: Seat.self, bufferingPolicy: .unbounded)
        let link = link
        let store = store
        let task = Task {
            await withDiscardingTaskGroup { group in
                group.addTask { await Self.relayRequests(from: link, game: game, into: continuation) }
                if let store {
                    group.addTask { await Self.admitSeated(link: link, store: store, game: game) }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Each new request at this table, as the seat the host would add.
    private static func relayRequests(from link: TableLink, game: GameID, into continuation: AsyncStream<Seat>.Continuation) async {
        var seen: Set<UUID> = []
        for await requests in Observations({ link.seatRequests }) {
            for request in requests where request.game == game && seen.insert(request.id).inserted {
                continuation.yield(seat(for: request))
            }
        }
    }

    /// Admits a waiting phone once someone at the table seats it.
    private static func admitSeated(link: TableLink, store: any GameStore, game: GameID) async {
        for await _ in store.updates(for: game) {
            guard !link.seatRequests.isEmpty, let state = try? await store.gameState(game) else { continue }
            for request in link.seatRequests where request.game == game {
                let seated = state.seats.contains { seat in
                    seat.deviceID == request.device || (request.person.map { seat.player == $0 } ?? false)
                }
                if seated { await link.answer(request, admit: true) }
            }
        }
    }

    /// The seat for a request: the person's own identity when the phone has one, otherwise a
    /// guest linked to that phone.
    static func seat(for request: SeatRequest) -> Seat {
        Seat(
            player: request.person ?? .guest(GuestID(request.device.rawValue)),
            displayName: request.displayName,
            order: 0,
            deviceID: request.device
        )
    }
}

extension NearbyTableDiscovery: TableInviting {
    func inviteLink(for game: GameID, at date: Date) -> URL? {
        guard link.game == game else { return nil }
        return link.inviteLink(at: date)
    }

    func prepareToJoin(_ game: GameID, inviteCode: String) {
        link.join(game, inviteCode: inviteCode)
    }
}
