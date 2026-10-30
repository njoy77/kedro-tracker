import Foundation
import Observation
import OSLog

/// The peer-to-peer link between phones at one table (design §5.2). Works with no internet.
///
/// **Topology: a star.** One phone is the hub: it advertises `_kedro-table._tcp` (Bonjour,
/// peer-to-peer), accepts connections and relays every operation batch to every other member.
/// Everyone else is a spoke with a single connection to the hub.
///
/// **Joining.** A phone browses for the game's hub. The host looks for 1 s, others for 3 s; if no
/// hub shows up, the phone becomes the hub itself (someone has to host so the others can find
/// the table). If two hubs ever see each other, the one with the higher rank (seat order, then
/// device ID) steps down and joins the other.
///
/// **Failover.** When a spoke loses its hub, the lowest online seat takes over: each remaining
/// member waits `failoverBase + rank × failoverStep` (rank among the last known members), browsing
/// meanwhile, and becomes hub only if nobody better appeared.
///
/// **Convergence.** On every connection both sides send an `inventory` of opIDs and answer with
/// what the other lacks. Operations are appended to the `GameStore` (idempotent) and folded in
/// HLC order by every phone, so all phones converge on the same state regardless of arrival order.
///
/// **Admission.** A phone that proves membership (table secret), is already seated (matched by
/// account), or has played with this phone's person is welcomed at once. Anyone else waits while
/// the table sees a seat request (J-02) that any seated phone can answer with `answer(_:admit:)`.
///
/// **Fallback.** With `NetworkFlags.multipeerFallback` on, a hub that has nobody connected after
/// 5 s also hosts over MultipeerConnectivity, and searching phones browse it too.
@Observable
final class TableLink {
    enum Role: Hashable, Sendable {
        case idle
        /// Looking for the table's hub.
        case searching
        /// Connected to the hub, waiting for a seated phone to answer our seat request.
        case awaitingAdmission
        case hub
        case spoke(hub: DeviceID)

        var isConnected: Bool {
            switch self {
            case .hub, .spoke: true
            case .idle, .searching, .awaitingAdmission: false
            }
        }
    }

    // MARK: Observable state

    private(set) var role: Role = .idle
    private(set) var game: GameID?
    /// Everyone on the link, this phone included (hub first).
    private(set) var members: [LinkMember] = []
    /// Strangers asking to sit (J-02). Answer with `answer(_:admit:)`.
    private(set) var seatRequests: [SeatRequest] = []
    private(set) var isUsingFallback = false
    /// Set when the table declined this phone.
    private(set) var lastRefusal: LinkRefusal?

    /// Other phones in sync over the link (for "Offline · n phones in sync").
    var connectedPeerCount: Int { role.isConnected ? max(0, members.count - 1) : 0 }

    // MARK: Dependencies

    @ObservationIgnored private let store: any GameStore
    @ObservationIgnored private let identity: () -> LocalIdentity
    @ObservationIgnored private let secrets: any TableSecretStore
    @ObservationIgnored private let networking: any TableLinkNetworking
    @ObservationIgnored private let fallback: (any TableLinkNetworking)?
    @ObservationIgnored private let isFallbackEnabled: () -> Bool
    @ObservationIgnored private let isPlayedWith: (PlayerRef) async -> Bool
    /// People this phone's person blocked: never admitted, and never put to the table as a seat
    /// request (design §5.9 "Rules", §8.3).
    @ObservationIgnored private let isBlocked: (PlayerRef) -> Bool
    /// Signs this phone's hellos and checks other phones' (nil: no identity admission at all).
    @ObservationIgnored private let linkIdentity: LinkIdentityService?
    @ObservationIgnored private let timing: TableLinkTiming
    /// Answers Nearby Interaction token exchanges from phones peeking at this table.
    @ObservationIgnored var nearbyTokens: (any NearbyTokenExchange)?
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "TableLink")

    // MARK: Runtime

    private struct HubConnection {
        var channel: any LinkChannel
        var hello: LinkHello?
        /// Set once admitted.
        var member: LinkMember?
        var isPeek = false
    }

    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var advertisedTable: AdvertisedTable?
    @ObservationIgnored private var hubConnections: [UUID: HubConnection] = [:]
    @ObservationIgnored private var pendingAdmissions: [UUID: UUID] = [:] // request ID → channel ID
    @ObservationIgnored private var hubChannel: (any LinkChannel)?
    @ObservationIgnored private var lastHeard: [UUID: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var lastKnownMembers: [LinkMember] = []
    @ObservationIgnored private var lostHub: DeviceID?
    @ObservationIgnored private var continuations: [GameID: [UUID: AsyncStream<[GameOperation]>.Continuation]] = [:]
    @ObservationIgnored private var inviteCodes: [GameID: String] = [:]

    /// - Parameters:
    ///   - identity: Who this phone is acting as (`AppModel.identity`).
    ///   - isPlayedWith: Whether this phone's person has played with someone (admits without asking).
    init(
        store: any GameStore,
        identity: @escaping () -> LocalIdentity,
        secrets: any TableSecretStore = KeychainTableSecretStore(),
        networking: any TableLinkNetworking = BonjourLinkNetworking(),
        fallback: (any TableLinkNetworking)? = nil,
        isFallbackEnabled: @escaping () -> Bool = { NetworkFlags.multipeerFallback },
        isPlayedWith: @escaping (PlayerRef) async -> Bool = { _ in false },
        isBlocked: @escaping (PlayerRef) -> Bool = { _ in false },
        linkIdentity: LinkIdentityService? = nil,
        timing: TableLinkTiming = .standard
    ) {
        self.isBlocked = isBlocked
        self.linkIdentity = linkIdentity
        self.store = store
        self.identity = identity
        self.secrets = secrets
        self.networking = networking
        self.fallback = fallback
        self.isFallbackEnabled = isFallbackEnabled
        self.isPlayedWith = isPlayedWith
        self.timing = timing
    }

    // MARK: Public API

    /// Starts linking with the phones at a game's table. Leaves any other table first.
    /// - Parameter inviteCode: The `k` from a scanned QR link, which admits without Ask to Sit.
    func join(_ game: GameID, inviteCode: String? = nil) {
        if let inviteCode { inviteCodes[game] = inviteCode }
        // Joining the same table again only matters after it stopped (declined, or left).
        guard self.game != game || role == .idle else { return }
        leave()
        self.game = game
        role = .searching
        lastRefusal = nil
        runTask = Task { [weak self] in await self?.run(game) }
    }

    /// Stops linking (says goodbye to connected phones).
    func leave() {
        runTask?.cancel()
        runTask = nil
        if let hubChannel {
            Task { try? await hubChannel.send(.goodbye); hubChannel.close() }
        }
        hubChannel = nil
        closeHubConnections()
        networking.stopHosting()
        fallback?.stopHosting()
        game = nil
        role = .idle
        members = []
        seatRequests = []
        lastKnownMembers = []
        lostHub = nil
        isUsingFallback = false
    }

    /// The lobby's advertisement (host name and table word overrides). Joins the game if needed.
    func advertise(_ table: AdvertisedTable) {
        advertisedTable = table
        if game != table.gameID {
            join(table.gameID)
        } else {
            Task { await refreshAdvertisement(table.gameID) }
        }
    }

    func stopAdvertising() {
        advertisedTable = nil
    }

    /// Sends operations to the other phones (local ones, or ones that arrived from the backend).
    /// While searching, nothing is sent: the inventory exchange on (re)connect catches everyone up.
    func broadcast(_ operations: [GameOperation]) {
        guard let game else { return }
        let relevant = operations.filter { $0.gameId == game }
        guard !relevant.isEmpty else { return }
        switch role {
        case .hub:
            relay(relevant, except: nil)
        case .spoke:
            if let hubChannel { send(relevant, on: hubChannel) }
        case .idle, .searching, .awaitingAdmission:
            break
        }
    }

    /// Operations arriving over the link for a game (already appended to the store).
    func incoming(for game: GameID) -> AsyncStream<[GameOperation]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [GameOperation].self, bufferingPolicy: .unbounded)
        let token = UUID()
        continuations[game, default: [:]][token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[game]?[token] = nil }
        }
        return stream
    }

    /// The link for the table's rotating QR code and AirDrop (design §5.8): `https://kedro.app/t/{id}?k={code}`.
    /// The code changes every 60 s, so regenerate it on a timer. nil when not at a table.
    func inviteLink(at date: Date = .now) -> URL? {
        guard let game else { return nil }
        let secret = secrets.secretCreatingIfNeeded(for: game)
        return TableInvite.link(for: game, inviteCode: TableKey.inviteCode(secret: secret, game: game, at: date))
    }

    /// Lets a stranger in, or not ("Let Jo In", J-02). Any seated phone may answer.
    func answer(_ request: SeatRequest, admit: Bool) async {
        seatRequests.removeAll { $0.id == request.id }
        switch role {
        case .hub:
            await resolveSeatRequest(request.id, admit: admit)
        case .spoke:
            try? await hubChannel?.send(.seatDecision(requestID: request.id, admit: admit))
        case .idle, .searching, .awaitingAdmission:
            break
        }
    }

    // MARK: Run loop

    private enum SpokeOutcome { case disconnected(hub: DeviceID), failed, refused }

    private func run(_ game: GameID) async {
        var isFirstSearch = true
        var excluded: Set<DeviceID> = []
        while !Task.isCancelled {
            let window = await searchWindow(for: game, isFirst: isFirstSearch)
            isFirstSearch = false
            if role != .awaitingAdmission { role = .searching }
            let skip = excluded.union(lostHub.map { [$0] } ?? [])
            excluded = []
            if let table = await findHub(for: game, within: window, excluding: skip) {
                switch await runAsSpoke(table, game: game) {
                case .disconnected(let hub):
                    lostHub = hub
                    members = []
                case .failed:
                    excluded = [table.advertisement.hub]
                    try? await Task.sleep(for: timing.retryDelay)
                case .refused:
                    role = .idle
                    members = []
                    return
                }
            } else if !Task.isCancelled {
                await runAsHub(game)
            }
        }
    }

    private func searchWindow(for game: GameID, isFirst: Bool) async -> Duration {
        let me = identity()
        if let lost = lostHub {
            let candidates = lastKnownMembers.filter { $0.device != lost }.sorted { $0.electionRank < $1.electionRank }
            let rank = candidates.firstIndex { $0.device == me.deviceID } ?? candidates.count
            return timing.failoverBase + timing.failoverStep * rank
        }
        guard isFirst else { return timing.retryDelay }
        let state = try? await store.gameState(game)
        if let mine = me.player?.seatID, let host = state?.hostSeat, host == mine {
            return timing.hostSearch
        }
        return timing.guestSearch
    }

    /// Browses until a hub for the game appears (best rank first) or the window closes.
    private func findHub(for game: GameID, within window: Duration, excluding: Set<DeviceID>) async -> DiscoveredTable? {
        let myDevice = identity().deviceID
        let matches: @Sendable (TableAdvertisement) -> Bool = { ad in
            ad.game == game && ad.hub != myDevice && !excluding.contains(ad.hub)
        }
        let fallbackDelay: Duration? = fallback == nil || !isFallbackEnabled() ? nil : (isUsingFallback ? .zero : timing.fallbackDelay)
        return await withTaskGroup(of: DiscoveredTable?.self) { group in
            group.addTask { await self.firstTable(onFallback: false, where: matches) }
            if let fallbackDelay {
                group.addTask {
                    try? await Task.sleep(for: fallbackDelay)
                    guard !Task.isCancelled else { return nil }
                    await self.markUsingFallback()
                    return await self.firstTable(onFallback: true, where: matches)
                }
            }
            group.addTask {
                try? await Task.sleep(for: window)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func markUsingFallback() {
        isUsingFallback = true
    }

    /// The best-ranked visible table matching `predicate`, waiting until one shows up.
    private func firstTable(onFallback: Bool, where predicate: @escaping @Sendable (TableAdvertisement) -> Bool) async -> DiscoveredTable? {
        guard let source = onFallback ? fallback : networking else { return nil }
        for await tables in source.browse() {
            let candidates = tables.filter { predicate($0.advertisement) }
            if let best = candidates.min(by: { $0.advertisement.hubRank < $1.advertisement.hubRank }) {
                return best
            }
        }
        return nil
    }

    // MARK: Spoke

    private func runAsSpoke(_ table: DiscoveredTable, game: GameID) async -> SpokeOutcome {
        guard let source = table.source == .multipeer ? fallback : networking else { return .failed }
        let channel: any LinkChannel
        do {
            channel = try await source.connect(to: table)
        } catch {
            log.info("Couldn't reach the hub: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
        hubChannel = channel
        let watchdog = startWatchdog(channel)
        defer {
            watchdog.cancel()
            channel.close()
            if hubChannel?.id == channel.id { hubChannel = nil }
            seatRequests = []
        }

        let me = identity()
        let proof = secrets.secret(for: game).map { TableKey.membershipProof(secret: $0, game: game, device: me.deviceID) }
        let hello = LinkHello(
            purpose: .join, game: game, device: me.deviceID, person: me.player, displayName: me.displayName,
            proof: proof, inviteCode: inviteCodes[game],
            identity: linkIdentity?.proof(game: game, device: me.deviceID, person: me.player)
        )
        do {
            try await channel.send(.hello(hello))
        } catch {
            return .failed
        }

        var welcomedBy: DeviceID?
        do {
            for try await message in channel.messages {
                lastHeard[channel.id] = .now
                switch message {
                case .welcome(let welcome):
                    welcomedBy = welcome.hub
                    secrets.save(welcome.tableSecret, for: game)
                    lostHub = nil
                    role = .spoke(hub: welcome.hub)
                    updateMembers(welcome.members)
                    try await sendInventory(for: game, on: channel)
                case .pending:
                    role = .awaitingAdmission
                case .refused(let reason):
                    lastRefusal = reason
                    return .refused
                case .members(let list):
                    updateMembers(list)
                case .inventory(let inventoryGame, let opIDs) where inventoryGame == game:
                    try await sendMissing(for: game, theirs: opIDs, on: channel)
                case .operations(let operations):
                    await ingest(operations, game: game, from: channel.id)
                case .seatRequest(let request):
                    if let person = request.person, isBlocked(person) {
                        // Someone this phone's person blocked never sits with them: say no for them.
                        try await channel.send(.seatDecision(requestID: request.id, admit: false))
                    } else if !seatRequests.contains(where: { $0.id == request.id }) {
                        seatRequests.append(request)
                    }
                case .seatRequestResolved(let id):
                    seatRequests.removeAll { $0.id == id }
                case .ping(let nonce):
                    try await channel.send(.pong(nonce))
                case .goodbye:
                    return welcomedBy.map { .disconnected(hub: $0) } ?? .failed
                default:
                    break
                }
            }
        } catch {
            log.info("Hub connection ended: \(error.localizedDescription, privacy: .public)")
        }
        return welcomedBy.map { .disconnected(hub: $0) } ?? .failed
    }

    private func updateMembers(_ list: [LinkMember]) {
        members = list
        lastKnownMembers = list
    }

    // MARK: Hub

    private func runAsHub(_ game: GameID) async {
        guard let state = try? await store.gameState(game) else {
            // Nothing stored for this game yet (e.g. opened from a link): we can't host it. Keep looking.
            try? await Task.sleep(for: timing.retryDelay)
            return
        }
        let me = identity()
        let advertisement = makeAdvertisement(state)
        let inbound: AsyncStream<any LinkChannel>
        do {
            inbound = try networking.startHosting(advertisement)
        } catch {
            log.error("Couldn't host the table: \(error.localizedDescription, privacy: .public)")
            try? await Task.sleep(for: timing.retryDelay)
            return
        }
        _ = secrets.secretCreatingIfNeeded(for: game)
        lostHub = nil
        role = .hub
        refreshMembers(state: state)
        let myRank = HubRank(seatOrder: mySeatOrder(in: state), device: me.deviceID)
        log.info("Hosting \(game.uuidString, privacy: .public)")

        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await self.acceptSpokes(inbound, game: game); return true }
            group.addTask { await self.keepAdvertisementCurrent(game); return false }
            group.addTask { await self.watchForBetterHub(game, myRank: myRank); return true }
            group.addTask { await self.hostOnFallbackIfAlone(game); return false }
            for await endsHub in group where endsHub {
                group.cancelAll()
                break
            }
            group.cancelAll()
        }

        networking.stopHosting()
        fallback?.stopHosting()
        closeHubConnections()
        if role == .hub { role = .searching }
        members = []
    }

    private func mySeatOrder(in state: GameState?) -> Int? {
        identity().player.flatMap { state?.seat(for: $0)?.order }
    }

    private func makeAdvertisement(_ state: GameState) -> TableAdvertisement {
        TableAdvertisement(state: state, table: advertisedTable, hub: identity().deviceID, hubSeatOrder: mySeatOrder(in: state))
    }

    private func acceptSpokes(_ inbound: AsyncStream<any LinkChannel>, game: GameID) async {
        await withDiscardingTaskGroup { group in
            for await channel in inbound {
                group.addTask { await self.serveSpoke(channel, game: game) }
            }
            group.cancelAll()
        }
    }

    private func serveSpoke(_ channel: any LinkChannel, game: GameID) async {
        hubConnections[channel.id] = HubConnection(channel: channel)
        let watchdog = startWatchdog(channel)
        defer {
            watchdog.cancel()
            channel.close()
            removeConnection(channel.id)
        }
        do {
            for try await message in channel.messages {
                lastHeard[channel.id] = .now
                let isMember = hubConnections[channel.id]?.member != nil
                switch message {
                case .hello(let hello):
                    guard hubConnections[channel.id]?.hello == nil else { continue }
                    guard try await handleHello(hello, on: channel, game: game) else { return }
                case .inventory(let inventoryGame, let opIDs) where isMember && inventoryGame == game:
                    try await sendMissing(for: game, theirs: opIDs, on: channel)
                case .operations(let operations) where isMember:
                    await ingest(operations, game: game, from: channel.id)
                case .seatDecision(let requestID, let admit) where isMember:
                    await resolveSeatRequest(requestID, admit: admit)
                case .nearbyToken(let token):
                    let peer = channel.id.uuidString
                    nearbyTokens?.didReceive(token, from: peer)
                    if let mine = nearbyTokens?.localToken(for: peer) {
                        try await channel.send(.nearbyToken(mine))
                    }
                case .ping(let nonce):
                    try await channel.send(.pong(nonce))
                case .goodbye:
                    return
                default:
                    break
                }
            }
        } catch {
            log.info("Spoke connection ended: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns false when the connection should close.
    private func handleHello(_ hello: LinkHello, on channel: any LinkChannel, game: GameID) async throws -> Bool {
        hubConnections[channel.id]?.hello = hello
        guard hello.version == LinkHello.currentVersion else {
            try await channel.send(.refused(.unsupportedVersion))
            return false
        }
        guard hello.game == game else {
            try await channel.send(.refused(.wrongGame))
            return false
        }
        if hello.purpose == .peek {
            hubConnections[channel.id]?.isPeek = true
            return true
        }
        let state = try? await store.gameState(game)
        switch await admission(for: hello, state: state, game: game) {
        case .admit:
            try await welcome(channel, hello: hello, state: state, game: game)
        case .refuse:
            try await channel.send(.refused(.declined))
            return false
        case .ask:
            let request = SeatRequest(id: UUID(), game: game, device: hello.device, person: hello.person, displayName: hello.displayName)
            pendingAdmissions[request.id] = channel.id
            seatRequests.append(request)
            try await channel.send(.pending(requestID: request.id))
            sendToMembers(.seatRequest(request))
        }
        return true
    }

    enum Admission: Equatable { case admit, ask, refuse }

    /// Who gets in (design §5.3):
    /// - never someone this phone's person blocked;
    /// - a phone that was admitted before (membership proof) or holds the QR code;
    /// - by identity (already seated, or played with), only with a verified identity proof: the
    ///   person in a hello is otherwise just what the other phone says;
    /// - everyone else asks to sit.
    func admission(for hello: LinkHello, state: GameState?, game: GameID) async -> Admission {
        if let person = hello.person, isBlocked(person) { return .refuse }
        if let proof = hello.proof, let secret = secrets.secret(for: game),
           TableKey.isValidProof(proof, secret: secret, game: game, device: hello.device) {
            return .admit
        }
        if let code = hello.inviteCode, let secret = secrets.secret(for: game),
           TableKey.isValidInviteCode(code, secret: secret, game: game) {
            return .admit
        }
        guard let person = hello.person, person.playerID != nil, linkIdentity?.verifies(hello) == true else { return .ask }
        // Seated already (the host added them, or they're rejoining): matched by account (§5.7).
        if state?.seat(for: person) != nil { return .admit }
        return await isPlayedWith(person) ? .admit : .ask
    }

    private func welcome(_ channel: any LinkChannel, hello: LinkHello, state: GameState?, game: GameID) async throws {
        // The same phone reconnecting replaces its old connection.
        for (id, connection) in hubConnections where id != channel.id && connection.member?.device == hello.device {
            connection.channel.close()
        }
        let order = hello.person.flatMap { state?.seat(for: $0)?.order }
        hubConnections[channel.id]?.member = LinkMember(device: hello.device, person: hello.person, displayName: hello.displayName, seatOrder: order, isHub: false)
        refreshMembers(state: state)
        let secret = secrets.secretCreatingIfNeeded(for: game)
        try await channel.send(.welcome(LinkWelcome(hub: identity().deviceID, tableSecret: secret, members: members)))
        sendToMembers(.members(members), except: channel.id)
        try await sendInventory(for: game, on: channel)
        for request in seatRequests {
            try await channel.send(.seatRequest(request))
        }
    }

    private func resolveSeatRequest(_ requestID: UUID, admit: Bool) async {
        seatRequests.removeAll { $0.id == requestID }
        guard let channelID = pendingAdmissions.removeValue(forKey: requestID) else { return }
        sendToMembers(.seatRequestResolved(requestID: requestID))
        guard let connection = hubConnections[channelID], let hello = connection.hello, let game else { return }
        if admit {
            let state = try? await store.gameState(game)
            try? await welcome(connection.channel, hello: hello, state: state, game: game)
        } else {
            try? await connection.channel.send(.refused(.declined))
            connection.channel.close()
        }
    }

    private func removeConnection(_ id: UUID) {
        guard let removed = hubConnections.removeValue(forKey: id) else { return }
        lastHeard[id] = nil
        if removed.isPeek { nearbyTokens?.endSession(for: id.uuidString) }
        for (requestID, channelID) in pendingAdmissions where channelID == id {
            pendingAdmissions[requestID] = nil
            seatRequests.removeAll { $0.id == requestID }
            sendToMembers(.seatRequestResolved(requestID: requestID))
        }
        if removed.member != nil, role == .hub {
            refreshMembers(state: nil)
            sendToMembers(.members(members))
        }
    }

    private func closeHubConnections() {
        for connection in hubConnections.values {
            let channel = connection.channel
            Task { try? await channel.send(.goodbye); channel.close() }
        }
        hubConnections = [:]
        pendingAdmissions = [:]
    }

    /// Recomputes `members` (hub first). With a state, seat orders are refreshed too.
    private func refreshMembers(state: GameState?) {
        let me = identity()
        let myOrder = state.map { mySeatOrder(in: $0) } ?? members.first { $0.device == me.deviceID }?.seatOrder
        var list = [LinkMember(device: me.deviceID, person: me.player, displayName: me.displayName, seatOrder: myOrder, isHub: true)]
        for (id, connection) in hubConnections.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard var member = connection.member else { continue }
            if let state {
                member.seatOrder = member.person.flatMap { state.seat(for: $0)?.order }
                hubConnections[id]?.member = member
            }
            list.append(member)
        }
        updateMembers(list)
    }

    private func keepAdvertisementCurrent(_ game: GameID) async {
        for await _ in store.updates(for: game) {
            await refreshAdvertisement(game)
        }
    }

    private func refreshAdvertisement(_ game: GameID) async {
        guard role == .hub, let state = try? await store.gameState(game) else { return }
        let advertisement = makeAdvertisement(state)
        networking.updateAdvertisement(advertisement)
        if isUsingFallback { fallback?.updateAdvertisement(advertisement) }
        let before = members
        refreshMembers(state: state)
        if members != before { sendToMembers(.members(members)) }
    }

    /// Returns when a better-ranked hub for the same game is visible (this hub then steps down).
    private func watchForBetterHub(_ game: GameID, myRank: HubRank) async {
        let myDevice = myRank.device
        let better: @Sendable (TableAdvertisement) -> Bool = { ad in
            ad.game == game && ad.hub != myDevice && ad.hubRank < myRank
        }
        let fallbackDelay: Duration? = fallback == nil || !isFallbackEnabled() ? nil : timing.fallbackDelay
        _ = await withTaskGroup(of: DiscoveredTable?.self) { group in
            group.addTask { await self.firstTable(onFallback: false, where: better) }
            if let fallbackDelay {
                group.addTask {
                    try? await Task.sleep(for: fallbackDelay)
                    guard !Task.isCancelled else { return nil }
                    return await self.firstTable(onFallback: true, where: better)
                }
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if !Task.isCancelled { log.info("A better hub is up; stepping down") }
    }

    /// After `fallbackDelay` with nobody connected, also hosts over MultipeerConnectivity.
    private func hostOnFallbackIfAlone(_ game: GameID) async {
        guard let fallback, isFallbackEnabled() else { return await sleepUntilCancelled() }
        try? await Task.sleep(for: timing.fallbackDelay)
        guard !Task.isCancelled, members.count <= 1, let state = try? await store.gameState(game),
              let inbound = try? fallback.startHosting(makeAdvertisement(state)) else {
            return await sleepUntilCancelled()
        }
        isUsingFallback = true
        await acceptSpokes(inbound, game: game)
    }

    private func sleepUntilCancelled() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    // MARK: Operations

    private func ingest(_ operations: [GameOperation], game: GameID, from source: UUID?) async {
        let relevant = operations.filter { $0.gameId == game }
        guard !relevant.isEmpty else { return }
        let new: [GameOperation]
        do {
            new = try await store.append(relevant)
        } catch {
            log.error("Couldn't store linked operations: \(error.localizedDescription, privacy: .public)")
            new = relevant
        }
        guard !new.isEmpty else { return }
        for continuation in (continuations[game] ?? [:]).values {
            continuation.yield(new)
        }
        if role == .hub {
            relay(new, except: source)
        }
    }

    /// Hub only: sends a batch to every admitted member except the one it came from.
    private func relay(_ operations: [GameOperation], except source: UUID?) {
        for (id, connection) in hubConnections where id != source && connection.member != nil {
            send(operations, on: connection.channel)
        }
    }

    private func send(_ operations: [GameOperation], on channel: any LinkChannel) {
        let batches = LinkFrame.batches(operations)
        Task {
            for batch in batches {
                try? await channel.send(.operations(batch))
            }
        }
    }

    private func sendToMembers(_ message: LinkMessage, except source: UUID? = nil) {
        for (id, connection) in hubConnections where id != source && connection.member != nil {
            let channel = connection.channel
            Task { try? await channel.send(message) }
        }
    }

    private func sendInventory(for game: GameID, on channel: any LinkChannel) async throws {
        let opIDs = (try? await store.operations(for: game).map(\.opId)) ?? []
        try await channel.send(.inventory(game: game, opIDs: opIDs))
    }

    private func sendMissing(for game: GameID, theirs: [UUID], on channel: any LinkChannel) async throws {
        let known = Set(theirs)
        let missing = ((try? await store.operations(for: game)) ?? []).filter { !known.contains($0.opId) }
        for batch in LinkFrame.batches(missing) {
            try await channel.send(.operations(batch))
        }
    }

    // MARK: Liveness

    /// Pings the channel every `pingInterval`; closes it after `peerTimeout` of silence.
    private func startWatchdog(_ channel: any LinkChannel) -> Task<Void, Never> {
        lastHeard[channel.id] = .now
        let timing = timing
        return Task { [weak self] in
            var nonce: UInt64 = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: timing.pingInterval)
                guard !Task.isCancelled, let self else { return }
                if let last = lastHeard[channel.id], ContinuousClock.now - last > timing.peerTimeout {
                    channel.close()
                    return
                }
                nonce += 1
                try? await channel.send(.ping(nonce))
            }
        }
    }
}

/// Timeouts for `TableLink` (shortened in tests).
nonisolated struct TableLinkTiming: Sendable {
    var hostSearch: Duration = .seconds(1)
    var guestSearch: Duration = .seconds(3)
    var failoverBase: Duration = .milliseconds(500)
    var failoverStep: Duration = .milliseconds(1500)
    var retryDelay: Duration = .seconds(1)
    /// "If no peer-to-peer path is up within 5 s" (design §5.2).
    var fallbackDelay: Duration = .seconds(5)
    var pingInterval: Duration = .seconds(5)
    var peerTimeout: Duration = .seconds(15)

    static let standard = TableLinkTiming()
}

/// Exchanges Nearby Interaction tokens with a peer (implemented by `NearbyRanger`).
protocol NearbyTokenExchange: AnyObject {
    /// This phone's token for a session with `peer`, creating the session if needed.
    func localToken(for peer: String) -> Data?
    /// Starts ranging with the peer's token.
    func didReceive(_ token: Data, from peer: String)
    func endSession(for peer: String)
}
