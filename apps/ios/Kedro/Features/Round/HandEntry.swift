import Foundation

/// A card in Card mode (design §7.3), valued per PRD §2.2.
nonisolated enum CardFace: String, Hashable, Sendable, CaseIterable, Identifiable {
    case ace, two, three, four, five, six, seven, eight, nine, ten, jack, queen, blackKing, redKing, joker

    /// How many red Kings a deck has: at most two per round (design §7.3).
    static let redKingsPerDeck = 2

    var id: String { rawValue }

    var value: Int {
        switch self {
        case .ace: 1
        case .two: 2
        case .three: 3
        case .four: 4
        case .five: 5
        case .six: 6
        case .seven: 7
        case .eight: 8
        case .nine: 9
        case .ten: 10
        case .jack: 11
        case .queen: 12
        case .blackKing: 13
        case .redKing: -1
        case .joker: 0
        }
    }

    /// The palette key: `A 2 … 10 J Q K♠♣ K♥♦ Joker`.
    var paletteLabel: String {
        switch self {
        case .ace: "A"
        case .jack: "J"
        case .queen: "Q"
        case .blackKing: "K♠♣"
        case .redKing: "K♥♦"
        case .joker: "Joker"
        default: String(value)
        }
    }

    /// The hand tray: "K♥ 3 7".
    var trayLabel: String {
        switch self {
        case .blackKing: "K♠"
        case .redKing: "K♥"
        default: paletteLabel
        }
    }

    var isRed: Bool { self == .redKing }

    /// VoiceOver: "Red King, minus 1".
    var accessibilityLabel: String {
        switch self {
        case .ace: "Ace, 1"
        case .jack: "Jack, 11"
        case .queen: "Queen, 12"
        case .blackKing: "Black King, 13"
        case .redKing: "Red King, minus 1"
        case .joker: "Joker, 0"
        default: String(value)
        }
    }
}

/// A number pad key (design §7.1).
nonisolated enum PadKey: Hashable, Sendable {
    case digit(Int)
    /// Toggles the sign (red Kings: −1 and −2).
    case minus
    case delete

    var label: String {
        switch self {
        case .digit(let digit): String(digit)
        case .minus: ScoreFormat.minus
        case .delete: "⌫"
        }
    }

    /// VoiceOver reads "minus", "delete", "1" (design §14).
    var accessibilityLabel: String {
        switch self {
        case .digit(let digit): String(digit)
        case .minus: "minus"
        case .delete: "delete"
        }
    }

    /// The pad, row by row: 1 2 3 / 4 5 6 / 7 8 9 / − 0 ⌫.
    static let layout: [[PadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.minus, .digit(0), .delete],
    ]
}

/// One player's hand as it's being entered: typed on the pad, or picked as cards.
///
/// Values stay within `Round.handRange` (−2…999): a keystroke that would leave the range is
/// refused (the key returns false), and negatives are capped by the red Kings still in the deck.
nonisolated enum HandEntry: Hashable, Sendable {
    case empty
    /// Digits as typed (at most 3), and whether the − key is on. `digits` may be empty while the
    /// sign is on ("−" waiting for its digit).
    case typed(digits: String, isNegative: Bool)
    /// Card mode: the cards picked, in order.
    case cards([CardFace])

    static let maxDigits = 3

    /// The hand value, or nil while nothing (or only "−") is in.
    var value: Int? {
        switch self {
        case .empty:
            return nil
        case let .typed(digits, isNegative):
            guard let magnitude = Int(digits) else { return nil }
            return isNegative ? -magnitude : magnitude
        case .cards(let cards):
            return cards.isEmpty ? nil : cards.reduce(0) { $0 + $1.value }
        }
    }

    var isEmpty: Bool { value == nil }

    /// The fewest red Kings this hand must hold: the cards picked, or a typed negative's size
    /// (only red Kings go below zero).
    var redKings: Int {
        switch self {
        case .empty: 0
        case .typed: max(0, -(value ?? 0))
        case .cards(let cards): cards.filter(\.isRed).count
        }
    }

    var cards: [CardFace] {
        if case .cards(let cards) = self { cards } else { [] }
    }

    /// What the value box shows: "12", "−1", "−" (sign waiting), "" when empty.
    var display: String {
        switch self {
        case .empty:
            return ""
        case let .typed(digits, isNegative):
            return (isNegative ? ScoreFormat.minus : "") + digits
        case .cards:
            return value.map(ScoreFormat.string) ?? ""
        }
    }

    /// The hand tray in Card mode: "K♥ 3 7 = 9".
    var trayText: String? {
        guard case .cards(let cards) = self, !cards.isEmpty, let value else { return nil }
        return cards.map(\.trayLabel).joined(separator: " ") + " = " + ScoreFormat.string(value)
    }

    /// Applies a pad key. `negativeLimit` is the most negative magnitude allowed (the red Kings
    /// still available, 0…2). Returns false (and leaves the entry unchanged) if the key is refused.
    mutating func press(_ key: PadKey, negativeLimit: Int) -> Bool {
        let (digits, isNegative): (String, Bool) = switch self {
        case .empty, .cards: ("", false)
        case let .typed(digits, isNegative): (digits, isNegative)
        }
        switch key {
        case .digit(let digit):
            guard (0...9).contains(digit) else { return false }
            let next = digits == "0" ? String(digit) : digits + String(digit)
            guard next.count <= Self.maxDigits else { return false }
            return apply(digits: next, isNegative: isNegative, negativeLimit: negativeLimit)
        case .minus:
            return apply(digits: digits, isNegative: !isNegative, negativeLimit: negativeLimit)
        case .delete:
            if case .cards(var cards) = self {
                guard !cards.isEmpty else { return false }
                cards.removeLast()
                self = cards.isEmpty ? .empty : .cards(cards)
                return true
            }
            if !digits.isEmpty {
                self = .typed(digits: String(digits.dropLast()), isNegative: isNegative)
                if case .typed("", false) = self { self = .empty }
                return true
            }
            if isNegative {
                self = .empty
                return true
            }
            return false
        }
    }

    /// Card mode: adds a card. Refused for a red King when none are left (`redKingsLeft` is 0).
    mutating func add(_ card: CardFace, redKingsLeft: Int) -> Bool {
        if card.isRed && redKingsLeft <= 0 { return false }
        var cards = self.cards
        cards.append(card)
        let total = cards.reduce(0) { $0 + $1.value }
        guard Round.handRange.contains(total) else { return false }
        self = .cards(cards)
        return true
    }

    private mutating func apply(digits: String, isNegative: Bool, negativeLimit: Int) -> Bool {
        guard !digits.isEmpty else {
            // Only the sign: "−" is waiting for its digit (allowed if any red King is left).
            if isNegative && negativeLimit <= 0 { return false }
            self = isNegative ? .typed(digits: "", isNegative: true) : .empty
            return true
        }
        guard let magnitude = Int(digits) else { return false }
        if isNegative {
            // Negative hands come only from red Kings: −1 or −2, never −0.
            guard magnitude >= 1, magnitude <= min(negativeLimit, -Round.handRange.lowerBound) else { return false }
        } else {
            guard magnitude <= Round.handRange.upperBound else { return false }
        }
        self = .typed(digits: digits, isNegative: isNegative)
        return true
    }

    /// An entry pre-filled with a saved value (corrections).
    init(value: Int) {
        self = .typed(digits: String(value.magnitude), isNegative: value < 0)
    }

    init() { self = .empty }
}
