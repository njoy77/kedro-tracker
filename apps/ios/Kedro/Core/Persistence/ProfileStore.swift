import Foundation
import Observation
import OSLog
import SwiftData

/// The person using this phone.
nonisolated struct LocalProfile: Hashable, Sendable {
    /// `.player` once signed in; `.guest` for "Play as a guest" (design §5.1).
    var identity: PlayerRef
    var displayName: String
    var handle: Handle?
    var avatar: Avatar?
    /// Displayed title (`TI-xx`).
    var titleID: String?
    /// Guest mode: claims this phone's guest history on sign-in. Never shown or logged.
    var claimToken: String?

    var seatID: SeatID { identity.seatID }
    var isGuest: Bool { identity.isGuest }

    /// A seat for this person at a new table.
    func seat(order: Int, device: DeviceID, languageLevel: LanguageLevel, gamesPlayed: Int?) -> Seat {
        Seat(
            player: identity, displayName: displayName, order: order, handle: handle, avatar: avatar,
            deviceID: device, languageLevel: languageLevel, titleID: titleID, gamesPlayed: gamesPlayed
        )
    }
}

/// Loads and saves the `LocalProfile`. Observable, so views update when it changes.
@Observable
final class ProfileStore {
    private(set) var profile: LocalProfile?
    /// Kept alive here: a `ModelContext` doesn't retain its container.
    @ObservationIgnored private let container: ModelContainer?
    @ObservationIgnored private let context: ModelContext?
    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "Profile")

    /// - Parameter container: nil keeps the profile in memory only (previews, tests).
    init(container: ModelContainer?, profile: LocalProfile? = nil) {
        self.container = container
        context = container?.mainContext
        self.profile = profile ?? Self.load(from: container?.mainContext)
    }

    /// Saves (or replaces) the profile.
    func save(_ profile: LocalProfile) {
        self.profile = profile
        guard let context else { return }
        do {
            let encoder = KedroJSON.encoder()
            let identity = try encoder.encode(profile.identity)
            let avatar = try profile.avatar.map { try encoder.encode($0) }
            if let existing = try context.fetch(FetchDescriptor<StoredProfile>()).first {
                existing.identity = identity
                existing.displayName = profile.displayName
                existing.handle = profile.handle?.rawValue
                existing.avatar = avatar
                existing.titleID = profile.titleID
                existing.claimToken = profile.claimToken
            } else {
                context.insert(StoredProfile(
                    identity: identity, displayName: profile.displayName, handle: profile.handle?.rawValue,
                    avatar: avatar, titleID: profile.titleID, claimToken: profile.claimToken
                ))
            }
            try context.save()
        } catch {
            log.error("Couldn't save the profile: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Forgets the profile (sign out of guest mode).
    func clear() {
        profile = nil
        guard let context else { return }
        do {
            try context.delete(model: StoredProfile.self)
            try context.save()
        } catch {
            log.error("Couldn't clear the profile: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from context: ModelContext?) -> LocalProfile? {
        guard let context, let stored = try? context.fetch(FetchDescriptor<StoredProfile>()).first else { return nil }
        let decoder = KedroJSON.decoder()
        guard let identity = try? decoder.decode(PlayerRef.self, from: stored.identity) else { return nil }
        return LocalProfile(
            identity: identity,
            displayName: stored.displayName,
            handle: stored.handle.flatMap(Handle.init),
            avatar: stored.avatar.flatMap { try? decoder.decode(Avatar.self, from: $0) },
            titleID: stored.titleID,
            claimToken: stored.claimToken
        )
    }
}

/// This installation's `DeviceID`, generated once and kept in `UserDefaults`.
enum DeviceIdentity {
    static let defaultsKey = "kedro.deviceID"

    static func current(defaults: UserDefaults = .standard) -> DeviceID {
        if let stored = defaults.string(forKey: defaultsKey), let id = DeviceID(uuidString: stored) {
            return id
        }
        let id = DeviceID()
        defaults.set(id.uuidString, forKey: defaultsKey)
        return id
    }
}
