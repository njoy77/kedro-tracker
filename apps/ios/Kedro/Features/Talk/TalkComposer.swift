import Foundation
import Observation
import OSLog

/// The Talk sheet's state and rules (design §8.1, §8.3): who it's at, which taunt, the rate
/// limits, and sending through the filter.
@Observable
final class TalkComposer {
    enum Mode: String, Hashable, CaseIterable, Identifiable {
        case canned, custom

        var id: String { rawValue }

        /// Literal tab labels.
        var title: String {
            switch self {
            case .canned: "Canned"
            case .custom: "Write your own"
            }
        }
    }

    /// Why Send didn't go through.
    enum Notice: Hashable {
        /// T-12: the filter blocked a custom taunt.
        case blocked
        /// T-10: out of taunts (or customs) this round.
        case rateLimited
        /// The game is over or the send failed.
        case failed(String)
    }

    let session: GameSession
    var target: TauntTarget {
        didSet { if target != oldValue { selectedTauntID = nil } }
    }
    var mode: Mode = .canned {
        didSet { notice = nil }
    }
    var selectedTauntID: String?
    /// The custom taunt, capped at 80 characters as it's typed.
    var customText = "" {
        didSet {
            if customText.count > TauntContent.customMaxLength {
                customText = String(customText.prefix(TauntContent.customMaxLength))
            }
            if notice == .blocked { notice = nil }
        }
    }
    private(set) var isSending = false
    var notice: Notice?

    @ObservationIgnored private let log = Logger(subsystem: "com.njoy77.kedro", category: "Talk")

    init(session: GameSession, target: TauntTarget) {
        self.session = session
        // Never at yourself.
        if case .seat(let seat) = target, seat == session.mySeatID {
            self.target = .table
        } else {
            self.target = target
        }
    }

    // MARK: Derived

    var state: GameState { session.state }

    /// Seats you can aim at: everyone at the table but you (design §8.3: only people seated here).
    var targetSeats: [Seat] { state.seats.filter { $0.id != session.mySeatID } }

    /// This sender's usage in the round being played.
    var allowance: TauntAllowance {
        TauntRateLimit.allowance(
            operations: session.operations, round: state.nextRoundNumber, seat: session.mySeatID, device: session.identity.deviceID
        )
    }

    /// Watchers (not seated) and under-18s send canned taunts only; so does anyone with custom
    /// taunts off.
    func canWriteCustom(preferences: AppPreferences) -> Bool {
        session.mySeat != nil && preferences.effectiveCustomTaunts
    }

    var sections: [TauntSection] {
        TauntLibrary.sections(for: TauntContext(state: state, target: target, sender: session.mySeatID))
    }

    var trimmedCustomText: String { TauntModerator.prepare(customText) }

    func canSend(preferences: AppPreferences) -> Bool {
        guard state.status.isLive, !isSending else { return false }
        switch mode {
        case .canned: return selectedTauntID != nil && allowance.canSend
        case .custom: return canWriteCustom(preferences: preferences) && !trimmedCustomText.isEmpty && allowance.canSendCustom
        }
    }

    /// Literal: "2 of 3 left this round".
    var allowanceText: String {
        let allowance = allowance
        var text = "\(allowance.remaining) of \(TauntRateLimit.perRound) left this round"
        if mode == .custom, allowance.canSend, !allowance.canSendCustom {
            text += " · custom one used"
        }
        return text
    }

    // MARK: Sending

    /// Sends the selected or written taunt. Returns true when it went out.
    func send(services: TalkServices, preferences: AppPreferences) async -> Bool {
        guard state.status.isLive else {
            notice = .failed(GameSession.SessionError.gameLocked.errorDescription ?? "")
            return false
        }
        let content: TauntContent
        switch mode {
        case .canned:
            guard let id = selectedTauntID else { return false }
            guard allowance.canSend else { notice = .rateLimited; return false }
            content = .canned(id: id)
        case .custom:
            guard canWriteCustom(preferences: preferences) else { return false }
            guard allowance.canSendCustom else { notice = .rateLimited; return false }
            isSending = true
            let verdict = await services.moderator.review(customText)
            isSending = false
            switch verdict {
            case .allowed(let text, _):
                content = .custom(text: text)
            case .blocked:
                notice = .blocked
                return false
            case .empty, .tooLong:
                return false
            }
            // The round may have moved on (or the limit filled) while the server checked.
            guard allowance.canSendCustom else { notice = .rateLimited; return false }
        }
        isSending = true
        defer { isSending = false }
        do {
            try await session.sendTaunt(content, to: target)
            notice = nil
            return true
        } catch {
            log.error("Couldn't send a taunt: \(error.localizedDescription, privacy: .public)")
            notice = .failed(error.localizedDescription)
            return false
        }
    }
}
