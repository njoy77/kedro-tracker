import Foundation
import Observation
import OSLog
import Supabase

/// Every networking service, built once at launch and installed into the `AppModel`:
/// the peer-to-peer `TableLink`, `BackendSync`, the combined `NetworkedTransport`, the
/// server-backed `RemotePlayerDirectory`, `NearbyTableDiscovery`, the Bluetooth
/// `NearbyAlertService` and `PushService`.
///
/// Wiring (foundation owns `KedroApp`):
/// ```swift
/// @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
/// // in init(), after creating `auth` and `appModel`:
/// network = NetworkServices.install(in: appModel, auth: auth)
/// // on the root view:
/// .environment(network)
/// .onOpenURL { network.push.handle($0) }
/// .task { pushDelegate.service = network.push; await network.run() }
/// ```
/// Features read `network.link.seatRequests` (J-02), `network.push.pendingInvite` (the Table
/// card) and `network.link.inviteLink()` (the QR code) from the environment.
@Observable
final class NetworkServices {
    let api: APIClient
    let link: TableLink
    let sync: BackendSync
    let transport: NetworkedTransport
    let directory: RemotePlayerDirectory
    let discovery: NearbyTableDiscovery
    let alerts: NearbyAlertService
    let push: PushService
    let path: any NetworkPathMonitoring

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let auth: AuthStore?
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "Network")

    /// Builds the services for an app model. `auth` supplies the Supabase client (tokens,
    /// Realtime); nil runs without an account (previews).
    init(
        app: AppModel,
        auth: AuthStore?,
        path: any NetworkPathMonitoring = NetworkPath(),
        syncStorage: any SyncQueueStorage = FileSyncQueueStorage(),
        secrets: any TableSecretStore = KeychainTableSecretStore(),
        playerCache: PlayerCache = PlayerCache()
    ) {
        if let auth { SupabaseAccessToken.register(auth.client) }
        self.app = app
        self.auth = auth
        self.path = path
        let api = app.api
        self.api = api
        let store = app.store
        let identity: () -> LocalIdentity = { [weak app] in
            app?.identity ?? LocalIdentity(deviceID: DeviceIdentity.current(), player: nil, displayName: "Someone")
        }
        let isAtLiveTable: () -> Bool = { [weak app] in
            guard let session = app?.liveGame else { return false }
            return session.state.status.isLive && session.mySeat != nil
        }

        let local = LocalPlayerDirectory(store: store) { [weak app] in app?.profile?.identity }
        let directory = RemotePlayerDirectory(api: api, local: local, cache: playerCache)
        self.directory = directory

        let bonjour = BonjourLinkNetworking()
        let link = TableLink(
            store: store,
            identity: identity,
            secrets: secrets,
            networking: bonjour,
            fallback: MultipeerLinkNetworking(device: app.deviceID),
            isPlayedWith: { await directory.hasPlayedWith($0) }
        )
        self.link = link

        let sync = BackendSync(api: api, store: store, storage: syncStorage)
        self.sync = sync
        let transport = NetworkedTransport(store: store, link: link, sync: sync, path: path, identity: identity, clock: app.clock)
        self.transport = transport

        let push = PushService(api: api)
        push.prefetch = { game in await sync.pull(game, full: true) }
        push.isAtLiveTable = isAtLiveTable
        self.push = push

        let preferences = app.preferences
        let alerts = NearbyAlertService(
            isEnabled: { preferences.nearbyAlertsEnabled },
            isPlayedWith: { await directory.hasPlayedWith(.player($0)) },
            displayName: { try? await directory.player($0)?.displayName },
            isAtLiveTable: isAtLiveTable,
            voice: { Voice(level: preferences.effectiveLanguageLevel) },
            notify: { id, body, invite in await push.postLocal(id: id, body: body, invite: invite) }
        )
        self.alerts = alerts

        let ranger = NearbyRanger.isSupported ? NearbyRanger() : nil
        link.nearbyTokens = ranger
        discovery = NearbyTableDiscovery(
            link: link, networking: bonjour, directory: directory, identity: identity, ranger: ranger, alerts: alerts
        )
    }

    /// Builds the services and installs the transport, directory and discovery into the app model.
    /// Call before `AppModel.start()` so resumed games use the real transport.
    @discardableResult
    static func install(in app: AppModel, auth: AuthStore) -> NetworkServices {
        let services = NetworkServices(app: app, auth: auth)
        app.transport = services.transport
        app.directory = services.directory
        app.discovery = services.discovery
        return services
    }

    /// Launch work, kept running for the app's lifetime (from the root `.task`): first sync,
    /// notification permission state, and following sign-in, opt-in and the live game.
    func run() async {
        await push.refreshAuthorization()
        alerts.refresh()
        await sync.reachabilityChanged()
        await withDiscardingTaskGroup { group in
            group.addTask { await self.followAccount() }
            group.addTask { await self.followNearbyOptIn() }
            group.addTask { await self.followLiveGame() }
        }
    }

    private func followAccount() async {
        guard let auth else { return }
        var last = auth.signedInUser
        for await user in Observations({ auth.signedInUser }) where user != last {
            last = user
            await sync.reachabilityChanged()
            await push.accountChanged()
        }
    }

    private func followNearbyOptIn() async {
        guard let preferences = app?.preferences else { return }
        for await _ in Observations({ preferences.nearbyAlertsEnabled }) {
            alerts.refresh()
        }
    }

    /// Beacons for the nearby alert while seated at a live table (design §5.4).
    private func followLiveGame() async {
        guard let app else { return }
        for await seat in Observations({ () -> LiveSeat? in
            guard let session = app.liveGame, session.state.status.isLive, let seat = session.mySeat else { return nil }
            return LiveSeat(game: session.gameID, person: seat.player)
        }) {
            if let seat {
                alerts.startBeacon(for: seat.person, game: seat.game)
            } else {
                alerts.stopBeacon()
            }
        }
    }

    /// Moves a guest's history onto the signed-in account (`POST /v1/claims`, design §5.1). Call
    /// from `AppModel.didSignIn` with the guest profile's claim token before clearing it; on
    /// success the claimed games are pulled again so their seats show the account.
    func claimGuestHistory(token: String) async -> ClaimResult? {
        do {
            let result = try await api.claim(token: token)
            for game in sync.connectedGames { await sync.pull(game, full: true) }
            return result
        } catch {
            log.info("Claim failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private struct LiveSeat: Hashable, Sendable {
        var game: GameID
        var person: PlayerRef
    }
}
