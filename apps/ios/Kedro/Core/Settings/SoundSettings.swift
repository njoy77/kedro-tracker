import Foundation
import Observation

/// The sound pack moments (design §3.8). Labels are literal.
nonisolated enum SoundMoment: String, Hashable, Sendable, CaseIterable, Identifiable {
    case liveKnock, knockLanded, knockTied, knockFailed, redKing, roundSaved, tauntReceived, winner, deadLast, debut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveKnock: "Live knock"
        case .knockLanded: "Knock landed"
        case .knockTied: "Knock tied"
        case .knockFailed: "Knock failed"
        case .redKing: "Red King"
        case .roundSaved: "Round saved"
        case .tauntReceived: "Taunt received"
        case .winner: "Winner"
        case .deadLast: "Dead last"
        case .debut: "Debut on the board"
        }
    }

    /// What it sounds like (Settings subtitle).
    var detail: String {
        switch self {
        case .liveKnock: "Two hard knuckle raps on wood"
        case .knockLanded: "A clean whip crack"
        case .knockTied: "A flat snare hit"
        case .knockFailed: "Crowd groan"
        case .redKing: "A low piano sting"
        case .roundSaved: "A card snapped onto the table"
        case .tauntReceived: "A short \"ooh\""
        case .winner: "The Kedro neigh"
        case .deadLast: "A sarcastic trombone"
        case .debut: "Gate bell"
        }
    }

    /// Who plays it.
    var audience: SoundAudience {
        switch self {
        case .roundSaved: .savingPhone
        case .tauntReceived: .recipient
        case .winner: .tableSpeakerThenEveryone
        default: .tableSpeaker
        }
    }
}

nonisolated enum SoundAudience: Hashable, Sendable {
    /// Only the table speaker (one phone per table).
    case tableSpeaker
    /// Only the phone that saved the round.
    case savingPhone
    /// The recipient's phone (or the table speaker for "the table").
    case recipient
    /// The table speaker, then every phone at game end.
    case tableSpeakerThenEveryone
}

/// "Be the table speaker" preference (design §3.8). The per-game claim is an operation
/// (`TableSpeakerClaimed`); this is the phone's standing preference.
nonisolated enum TableSpeakerPreference: String, Hashable, Sendable, CaseIterable {
    /// Display mode phone, else the scorekeeper, else the host.
    case automatic
    /// Claim it whenever this phone is at a table.
    case always
    /// Never play shared moments on this phone.
    case never

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .always: "This Phone"
        case .never: "Never"
        }
    }
}

/// Sound pack settings: a master switch (off by default), a toggle per moment, and the table
/// speaker preference. Persisted in `UserDefaults`.
@Observable
final class SoundSettings {
    enum Key {
        static let isEnabled = "kedro.sounds.enabled"
        static let tableSpeaker = "kedro.sounds.tableSpeaker"
        static func moment(_ moment: SoundMoment) -> String { "kedro.sounds.\(moment.rawValue)" }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Master switch. Off by default (design §3.8).
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }

    var tableSpeaker: TableSpeakerPreference {
        didSet { defaults.set(tableSpeaker.rawValue, forKey: Key.tableSpeaker) }
    }

    /// Per-moment toggles (all on by default, gated by the master switch).
    private(set) var enabledMoments: Set<SoundMoment>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        tableSpeaker = defaults.string(forKey: Key.tableSpeaker).flatMap(TableSpeakerPreference.init(rawValue:)) ?? .automatic
        enabledMoments = Set(SoundMoment.allCases.filter { defaults.object(forKey: Key.moment($0)) as? Bool ?? true })
    }

    /// Whether a moment should play on this phone (master switch and its toggle).
    func plays(_ moment: SoundMoment) -> Bool { isEnabled && enabledMoments.contains(moment) }

    func isOn(_ moment: SoundMoment) -> Bool { enabledMoments.contains(moment) }

    func set(_ moment: SoundMoment, on: Bool) {
        if on { enabledMoments.insert(moment) } else { enabledMoments.remove(moment) }
        defaults.set(on, forKey: Key.moment(moment))
    }
}
