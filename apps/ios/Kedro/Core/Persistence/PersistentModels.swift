import Foundation
import SwiftData

/// One stored operation. The full operation is kept as its contract JSON (`payload`), so the
/// local store and the API never drift; the other columns exist for querying.
@Model
final class StoredOperation {
    @Attribute(.unique) var opId: UUID
    var gameId: UUID
    /// `HLC.stringValue`; sorts like the HLC.
    var hlc: String
    var deviceId: UUID
    /// `OperationType.rawValue`.
    var type: String
    /// The operation encoded with `KedroJSON.encoder()`.
    var payload: Data
    var storedAt: Date

    #Index<StoredOperation>([\.gameId])

    init(opId: UUID, gameId: UUID, hlc: String, deviceId: UUID, type: String, payload: Data, storedAt: Date = .now) {
        self.opId = opId
        self.gameId = gameId
        self.hlc = hlc
        self.deviceId = deviceId
        self.type = type
        self.payload = payload
        self.storedAt = storedAt
    }
}

/// A Kedro player this phone knows about (from search results or shared games). A cache for the
/// local `PlayerDirectory`; the server is the source of truth for profiles.
@Model
final class StoredPlayer {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var handle: String
    /// `Avatar` as JSON.
    var avatar: Data?
    var titleID: String?
    var gamesPlayed: Int?
    var updatedAt: Date

    init(id: UUID, displayName: String, handle: String, avatar: Data?, titleID: String?, gamesPlayed: Int?, updatedAt: Date = .now) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.avatar = avatar
        self.titleID = titleID
        self.gamesPlayed = gamesPlayed
        self.updatedAt = updatedAt
    }
}

/// A guest identity created on this phone, with the claim token handed to them at game end.
@Model
final class StoredGuest {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Claim token for this guest's history (PRD §3.2). Never logged or shown in full.
    var claimToken: String?
    var createdAt: Date

    init(id: UUID, name: String, claimToken: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.claimToken = claimToken
        self.createdAt = createdAt
    }
}

/// The person using this phone (exactly one row, key "me").
@Model
final class StoredProfile {
    @Attribute(.unique) var key: String
    /// `PlayerRef` as JSON: `.player` once signed in, `.guest` for "Play as a guest".
    var identity: Data
    var displayName: String
    var handle: String?
    /// `Avatar` as JSON.
    var avatar: Data?
    var titleID: String?
    /// Guest mode: the token that claims this phone's guest history on sign-in (design §5.1).
    var claimToken: String?
    var createdAt: Date

    init(identity: Data, displayName: String, handle: String?, avatar: Data?, titleID: String?, claimToken: String?, createdAt: Date = .now) {
        key = "me"
        self.identity = identity
        self.displayName = displayName
        self.handle = handle
        self.avatar = avatar
        self.titleID = titleID
        self.claimToken = claimToken
        self.createdAt = createdAt
    }
}

/// The app's SwiftData schema and container.
enum KedroPersistence {
    static let schema = Schema([StoredOperation.self, StoredPlayer.self, StoredGuest.self, StoredProfile.self])

    /// The on-disk container (or an in-memory one for previews and tests).
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration("Kedro", schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
