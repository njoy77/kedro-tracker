import CoreBluetooth
import Foundation
import Observation
import OSLog

/// The opt-in nearby alert (design §5.4): "Maya started a table nearby." (N-07).
///
/// - **Beacon** (foreground, while seated, opted in): advertises the Kedro service UUID and serves
///   one read-only characteristic holding the seated player's ID and the game ID (32 bytes).
/// - **Scanner** (opted in, background too): scans for the service UUID, connects briefly to read
///   the characteristic, and posts N-07 when `NearbyAlertPolicy` allows it: played-with only,
///   never during your own game, at most 3 a day, once per table.
///
/// Bluetooth is never used for game state, and nothing here promises distance ("nearby", never
/// "at your table"). Bluetooth permission is only requested once the player opts in, because the
/// managers are created lazily.
///
/// Callbacks are delivered on the main queue (`queue: nil`).
@Observable
final class NearbyAlertService: NSObject {
    nonisolated static var serviceUUID: CBUUID { CBUUID(string: "6B3D0F2A-4C1E-4E8B-9A52-0D6E4B7C1A01") }
    nonisolated static var beaconCharacteristicUUID: CBUUID { CBUUID(string: "6B3D0F2A-4C1E-4E8B-9A52-0D6E4B7C1A02") }
    static let restoreIdentifier = "com.njoy77.kedro.nearby-alert"

    private(set) var isBeaconing = false
    private(set) var isScanning = false

    @ObservationIgnored private let isEnabled: () -> Bool
    @ObservationIgnored private let isPlayedWith: (PlayerID) async -> Bool
    @ObservationIgnored private let displayName: (PlayerID) async -> String?
    @ObservationIgnored private let isAtLiveTable: () -> Bool
    @ObservationIgnored private let voice: () -> Voice
    @ObservationIgnored private let notify: (_ id: String, _ body: String, _ invite: TableInvite) async -> Void
    @ObservationIgnored private var policy: NearbyAlertPolicy
    @ObservationIgnored private let defaults: UserDefaults

    @ObservationIgnored private var peripheralManager: CBPeripheralManager?
    @ObservationIgnored private var centralManager: CBCentralManager?
    @ObservationIgnored private var beacon: NearbyBeacon?
    @ObservationIgnored private var connecting: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var recentlyRead: [UUID: Date] = [:]
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "NearbyAlert")

    private enum Key {
        static let policy = "kedro.nearbyAlert.policy"
    }

    init(
        isEnabled: @escaping () -> Bool,
        isPlayedWith: @escaping (PlayerID) async -> Bool,
        displayName: @escaping (PlayerID) async -> String?,
        isAtLiveTable: @escaping () -> Bool,
        voice: @escaping () -> Voice,
        notify: @escaping (_ id: String, _ body: String, _ invite: TableInvite) async -> Void,
        defaults: UserDefaults = .standard
    ) {
        self.isEnabled = isEnabled
        self.isPlayedWith = isPlayedWith
        self.displayName = displayName
        self.isAtLiveTable = isAtLiveTable
        self.voice = voice
        self.notify = notify
        self.defaults = defaults
        policy = defaults.data(forKey: Key.policy).flatMap { try? JSONDecoder().decode(NearbyAlertPolicy.self, from: $0) } ?? NearbyAlertPolicy()
        super.init()
    }

    // MARK: Opt-in

    /// Call when the opt-in changes and at launch: starts or stops background scanning.
    func refresh() {
        if isEnabled() {
            startScanning()
        } else {
            stopScanning()
            stopBeacon()
        }
    }

    // MARK: Beacon

    /// Advertises while this phone is seated at a table (foreground only; iOS stops peripheral
    /// advertising of local data in the background). Guests have no played-with identity, so
    /// they don't beacon.
    func startBeacon(for person: PlayerRef?, game: GameID) {
        guard isEnabled(), case .player(let player) = person else { return stopBeacon() }
        let next = NearbyBeacon(player: player, game: game)
        guard next != beacon || !isBeaconing else { return }
        beacon = next
        if let manager = peripheralManager {
            if manager.state == .poweredOn { publishBeacon(on: manager) }
        } else {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        }
    }

    func stopBeacon() {
        beacon = nil
        guard let manager = peripheralManager else { return }
        manager.stopAdvertising()
        manager.removeAllServices()
        isBeaconing = false
    }

    private func publishBeacon(on manager: CBPeripheralManager) {
        guard let beacon else { return }
        manager.stopAdvertising()
        manager.removeAllServices()
        let characteristic = CBMutableCharacteristic(
            type: Self.beaconCharacteristicUUID, properties: [.read], value: beacon.encoded, permissions: [.readable]
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        manager.add(service)
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
        isBeaconing = true
    }

    // MARK: Scanner

    private func startScanning() {
        if let manager = centralManager {
            if manager.state == .poweredOn, !manager.isScanning { scan(on: manager) }
        } else {
            centralManager = CBCentralManager(
                delegate: self, queue: nil,
                options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
            )
        }
    }

    private func stopScanning() {
        centralManager?.stopScan()
        for peripheral in connecting.values { centralManager?.cancelPeripheralConnection(peripheral) }
        connecting = [:]
        isScanning = false
    }

    private func scan(on manager: CBCentralManager) {
        // Background scanning requires an explicit service list and coalesces duplicates.
        manager.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        isScanning = true
    }

    private func discovered(_ peripheral: CBPeripheral, on manager: CBCentralManager) {
        let id = peripheral.identifier
        // Each phone is read at most every 10 minutes; reading costs a connection.
        if let last = recentlyRead[id], Date.now.timeIntervalSince(last) < 600 { return }
        guard connecting[id] == nil, !isAtLiveTable(), policy.hasAlertsLeft(on: .now) else { return }
        recentlyRead[id] = .now
        connecting[id] = peripheral
        peripheral.delegate = self
        manager.connect(peripheral)
    }

    private func finish(_ peripheral: CBPeripheral) {
        connecting[peripheral.identifier] = nil
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    private func read(_ beacon: NearbyBeacon) async {
        guard isEnabled(), !isAtLiveTable(), await isPlayedWith(beacon.player) else { return }
        guard policy.shouldAlert(for: beacon.game, on: .now) else { return }
        guard let name = await displayName(beacon.player) else { return }
        policy.record(beacon.game, on: .now)
        if let data = try? JSONEncoder().encode(policy) { defaults.set(data, forKey: Key.policy) }
        let invite = TableInvite(gameID: beacon.game, source: .nearbyAlert, hostName: name)
        await notify("nearby-\(beacon.game.uuidString)", voice().line("N-07", ["name": name]), invite)
    }
}

// MARK: - Delegates

// `@preconcurrency`: CoreBluetooth calls these on the queue the managers were created with, which
// is the main queue (`queue: nil`), so they run main-actor isolated (checked at runtime).

extension NearbyAlertService: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            publishBeacon(on: peripheral)
        } else {
            isBeaconing = false
        }
    }
}

extension NearbyAlertService: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, isEnabled() {
            scan(on: central)
        } else {
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // Relaunched in the background by a scan result: scanning resumes in didUpdateState.
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        discovered(peripheral, on: central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        connecting[peripheral.identifier] = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        connecting[peripheral.identifier] = nil
    }
}

extension NearbyAlertService: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            return finish(peripheral)
        }
        peripheral.discoverCharacteristics([Self.beaconCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.beaconCharacteristicUUID }) else {
            return finish(peripheral)
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        let beacon = characteristic.value.flatMap(NearbyBeacon.init(encoded:))
        finish(peripheral)
        if let beacon { Task { await read(beacon) } }
    }
}

// MARK: - Beacon payload and policy

/// What the beacon characteristic holds: the seated player's ID and the game ID, 16 bytes each.
/// TODO(networking): anyone in Bluetooth range can read these two IDs; rotate an opaque token
/// per game (resolved by the backend for played-with pairs) once the API has an endpoint for it.
nonisolated struct NearbyBeacon: Hashable, Sendable {
    var player: PlayerID
    var game: GameID

    var encoded: Data {
        Self.bytes(player.rawValue) + Self.bytes(game.rawValue)
    }

    init(player: PlayerID, game: GameID) {
        self.player = player
        self.game = game
    }

    init?(encoded data: Data) {
        guard data.count == 32 else { return nil }
        let bytes = [UInt8](data)
        player = PlayerID(Self.uuid(bytes[0..<16]))
        game = GameID(Self.uuid(bytes[16..<32]))
    }

    private static func bytes(_ uuid: UUID) -> Data {
        withUnsafeBytes(of: uuid.uuid) { Data($0) }
    }

    private static func uuid(_ bytes: ArraySlice<UInt8>) -> UUID {
        let b = Array(bytes)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

/// The nearby alert's limits (design §5.4): at most `dailyLimit` alerts per calendar day and one
/// per table.
nonisolated struct NearbyAlertPolicy: Codable, Hashable, Sendable {
    static let dailyLimit = 3

    /// Alerts sent, newest last (only the last couple of days are kept).
    private(set) var sent: [Sent] = []

    nonisolated struct Sent: Codable, Hashable, Sendable {
        var game: GameID
        var at: Date
    }

    func hasAlertsLeft(on date: Date, calendar: Calendar = .current) -> Bool {
        sent.filter { calendar.isDate($0.at, inSameDayAs: date) }.count < Self.dailyLimit
    }

    func shouldAlert(for game: GameID, on date: Date, calendar: Calendar = .current) -> Bool {
        hasAlertsLeft(on: date, calendar: calendar) && !sent.contains { $0.game == game }
    }

    mutating func record(_ game: GameID, on date: Date) {
        sent.append(Sent(game: game, at: date))
        sent.removeAll { date.timeIntervalSince($0.at) > 2 * 86_400 }
    }
}
