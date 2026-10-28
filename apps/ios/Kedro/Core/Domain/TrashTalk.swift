import Foundation

/// Who a taunt is aimed at (design §8.1).
/// JSON: `{"kind":"table"}` or `{"kind":"seat","seatId":"p:…"}`.
nonisolated enum TauntTarget: Hashable, Sendable, Codable {
    case table
    case seat(SeatID)

    private enum CodingKeys: String, CodingKey { case kind, seatId }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "table": self = .table
        case "seat": self = .seat(try container.decode(SeatID.self, forKey: .seatId))
        case let kind:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown target \(kind)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .table:
            try container.encode("table", forKey: .kind)
        case .seat(let seat):
            try container.encode("seat", forKey: .kind)
            try container.encode(seat, forKey: .seatId)
        }
    }
}

/// What a taunt says. Canned taunts carry a copy ID (`TT-xx`) and render in each recipient's
/// language level; custom ones carry the sender's text (80 characters max, filtered).
/// JSON: `{"kind":"canned","id":"TT-01"}` or `{"kind":"custom","text":"…"}`.
nonisolated enum TauntContent: Hashable, Sendable, Codable {
    case canned(id: String)
    case custom(text: String)

    static let customMaxLength = 80

    var isCustom: Bool {
        if case .custom = self { true } else { false }
    }

    private enum CodingKeys: String, CodingKey { case kind, id, text }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "canned": self = .canned(id: try container.decode(String.self, forKey: .id))
        case "custom": self = .custom(text: try container.decode(String.self, forKey: .text))
        case let kind:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown taunt \(kind)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .canned(let id):
            try container.encode("canned", forKey: .kind)
            try container.encode(id, forKey: .id)
        case .custom(let text):
            try container.encode("custom", forKey: .kind)
            try container.encode(text, forKey: .text)
        }
    }
}

/// The five quick reactions on the last-round card (design §6.1). One per player per round.
/// JSON: the emoji's name, e.g. `"fire"`.
nonisolated enum Reaction: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case fire, skull, clown, laugh, salute

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .fire: "🔥"
        case .skull: "💀"
        case .clown: "🤡"
        case .laugh: "😂"
        case .salute: "🫡"
        }
    }

    /// Literal accessibility label.
    var accessibilityLabel: String {
        switch self {
        case .fire: "Fire"
        case .skull: "Skull"
        case .clown: "Clown"
        case .laugh: "Laughing"
        case .salute: "Salute"
        }
    }
}
