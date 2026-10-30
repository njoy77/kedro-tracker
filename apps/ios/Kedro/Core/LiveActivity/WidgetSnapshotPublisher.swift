import Foundation
import Observation
import WidgetKit

/// Writes the home and Lock Screen widgets' snapshot to the app group and reloads them
/// (design §13.3). Widgets never compute anything: stats builds the `WidgetSnapshot` (rank,
/// rating, rivalry line, next badge, all rendered in the player's level) and hands it here.
///
/// Widgets reload only when a game finishes and on claims, so they stay **frozen during live
/// games**: while `isFrozen` (set by `.liveGameActivity()` while this phone's game is active), a
/// published snapshot waits and is written when the game ends.
///
/// Reach it from the environment as an optional:
/// `@Environment(WidgetSnapshotPublisher.self) private var widgets: WidgetSnapshotPublisher?`.
@Observable
final class WidgetSnapshotPublisher {
    enum Reason: String, Sendable {
        /// A game this player was in finished (or was abandoned).
        case gameFinished
        /// Guest history was claimed, or the profile changed (name, avatar).
        case claim
    }

    /// True while a live game is in progress on this phone.
    var isFrozen = false {
        didSet {
            if !isFrozen, oldValue { flush() }
        }
    }

    /// A snapshot published while frozen.
    private(set) var pending: WidgetSnapshot?

    @ObservationIgnored private let store: WidgetSnapshotStore
    @ObservationIgnored private let reload: @MainActor () -> Void

    init(
        store: WidgetSnapshotStore = WidgetSnapshotStore(),
        reload: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.store = store
        self.reload = reload
    }

    /// The snapshot the widgets are showing (or will show).
    var current: WidgetSnapshot? { pending ?? store.load() }

    /// Publishes a new snapshot. Written now, or when the live game ends.
    func publish(_ snapshot: WidgetSnapshot, reason: Reason) {
        pending = snapshot
        guard !isFrozen else { return }
        flush()
    }

    private func flush() {
        guard let snapshot = pending else { return }
        do {
            try store.save(snapshot)
            pending = nil
            reload()
        } catch {
            // Keep it pending; the next publish or unfreeze retries.
        }
    }
}
