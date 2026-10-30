import Foundation
import Observation
import OSLog

/// Watches a live game and reacts on this phone: a toast for every new taunt it shows (design
/// §8.1, "a toast on every seated phone"), and the sound pack moments it should play (§3.8).
/// Run by `TalkServices.hold(_:app:)`; one per game.
///
/// Only changes after the monitor starts count: opening the Table never replays old taunts.
final class LiveTalkMonitor {
    private let session: GameSession
    private let app: AppModel
    private let services: TalkServices
    private var toastedTaunts: Set<UUID> = []
    private let log = Logger(subsystem: "com.njoy77.kedro", category: "Talk")

    init(session: GameSession, app: AppModel, services: TalkServices) {
        self.session = session
        self.app = app
        self.services = services
    }

    func run() async {
        var previous = session.state
        toastedTaunts = Set(previous.taunts.map(\.tauntId))
        await claimSpeakerIfPreferred(previous)
        let states = Observations { [session] in session.state }
        for await state in states {
            guard !Task.isCancelled else { return }
            guard state != previous else { continue }
            react(from: previous, to: state)
            previous = state
        }
    }

    /// Handles one change (internal for tests).
    func react(from old: GameState, to new: GameState) {
        let visible = services.visibleTaunts(in: new, preferences: app.preferences)
        let fresh = visible.filter { toastedTaunts.insert($0.tauntId).inserted && !isMine($0) }
        for taunt in fresh {
            showToast(for: taunt, in: new)
        }
        // Everything new is "seen", including hidden ones, so unmuting later doesn't replay them.
        toastedTaunts.formUnion(new.taunts.map(\.tauntId))

        let cues = SoundCues.cues(from: old, to: new, listener: listener(for: new, visible: visible))
        guard !cues.isEmpty else { return }
        let sound = services.sound
        let settings = app.preferences.sounds
        Task { await sound.play(cues, settings: settings) }
    }

    // MARK: Private

    private func isMine(_ taunt: TauntRecord) -> Bool {
        if let seat = session.mySeatID, taunt.from == seat { return true }
        return session.operations.first { $0.opId == taunt.opId }?.deviceId == session.identity.deviceID
    }

    private func showToast(for taunt: TauntRecord, in state: GameState) {
        let level = app.preferences.effectiveLanguageLevel
        guard let text = TauntRendering.text(taunt.content, level: level, filter: services.filter) else { return }
        let sender = taunt.from.flatMap { state.seat($0) }
        let gameID = state.gameID
        let services = services
        let app = app
        app.toasts.show(Toast(
            kind: .taunt,
            avatar: sender?.avatar,
            avatarName: sender?.displayName ?? taunt.fromName,
            avatarIsGuest: sender?.isGuest ?? true,
            eyebrow: TauntRendering.eyebrow(for: taunt, in: state),
            message: text,
            onTap: {
                services.feedRequest = gameID
                app.presentTable()
            },
            duration: .seconds(4),
            announcement: TauntRendering.announcement(for: taunt, text: text, in: state)
        ))
    }

    private func listener(for state: GameState, visible: [TauntRecord]) -> SoundListener {
        let preferences = app.preferences
        let device = session.identity.deviceID
        // Other seats: their first 3 games. This phone's own seat follows its learner hints setting.
        var learners = Set(state.seats.filter(\.isLearner).map(\.id))
        if let me = session.mySeat {
            if preferences.showsLearnerHints(gamesPlayed: me.gamesPlayed ?? 0) {
                learners.insert(me.id)
            } else {
                learners.remove(me.id)
            }
        }
        let visibleIDs = Set(visible.map(\.tauntId))
        return SoundListener(
            device: device,
            seat: session.mySeatID,
            isTableSpeaker: TableSpeaker.isThisPhone(device, state: state, preference: preferences.sounds.tableSpeaker),
            learners: learners,
            deviceForOperation: Dictionary(session.operations.map { ($0.opId, $0.deviceId) }, uniquingKeysWith: { first, _ in first }),
            hiddenTaunts: Set(state.taunts.map(\.tauntId)).subtracting(visibleIDs)
        )
    }

    private func claimSpeakerIfPreferred(_ state: GameState) async {
        let device = session.identity.deviceID
        guard TableSpeaker.shouldClaim(device, state: state, preference: app.preferences.sounds.tableSpeaker) else { return }
        do {
            try await session.claimTableSpeaker()
        } catch {
            log.error("Couldn't claim the table speaker: \(error.localizedDescription, privacy: .public)")
        }
    }
}
