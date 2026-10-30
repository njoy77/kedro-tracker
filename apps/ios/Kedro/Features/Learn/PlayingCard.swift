import SwiftUI

/// A real playing card for teaching (design §13.1): its face and its Cambio value (PRD §2.2).
nonisolated struct PlayingCard: Hashable, Sendable, Identifiable {
    enum Suit: String, Hashable, Sendable, CaseIterable {
        case spades = "♠", hearts = "♥", diamonds = "♦", clubs = "♣"

        var isRed: Bool { self == .hearts || self == .diamonds }

        var name: String {
            switch self {
            case .spades: "spades"
            case .hearts: "hearts"
            case .diamonds: "diamonds"
            case .clubs: "clubs"
            }
        }
    }

    enum Rank: Hashable, Sendable {
        case ace
        case number(Int)
        case jack, queen, king
        case joker

        var symbol: String {
            switch self {
            case .ace: "A"
            case .number(let value): "\(value)"
            case .jack: "J"
            case .queen: "Q"
            case .king: "K"
            case .joker: "★"
            }
        }

        var name: String {
            switch self {
            case .ace: "Ace"
            case .number(let value): "\(value)"
            case .jack: "Jack"
            case .queen: "Queen"
            case .king: "King"
            case .joker: "Joker"
            }
        }
    }

    var rank: Rank
    /// nil for a Joker.
    var suit: Suit?

    var id: String { "\(rank.symbol)\(suit?.rawValue ?? "")" }

    static func card(_ rank: Rank, _ suit: Suit) -> PlayingCard { PlayingCard(rank: rank, suit: suit) }
    static let joker = PlayingCard(rank: .joker, suit: nil)

    /// Points (PRD §2.2): Ace 1, 2–10 face value, Jack 11, Queen 12, black King 13, red King −1,
    /// Joker 0.
    var value: Int {
        switch rank {
        case .ace: 1
        case .number(let value): value
        case .jack: 11
        case .queen: 12
        case .king: (suit?.isRed ?? false) ? -1 : 13
        case .joker: 0
        }
    }

    var isRed: Bool { suit?.isRed ?? false }

    /// The card's power when discarded (PRD §2.3), if any.
    var power: String? {
        switch rank {
        case .number(7), .number(8): "Peek at one of your own cards."
        case .number(9), .number(10): "Peek at one of an opponent's cards."
        case .jack, .queen: "Blind switch: swap one of yours with an opponent's, no looking."
        case .king where !isRed: "Look at any card, then swap it if you want."
        default: nil
        }
    }

    /// "Red King of hearts, minus 1"
    var spokenName: String {
        let base: String
        if rank == .joker {
            base = "Joker"
        } else if let suit {
            base = (rank == .king ? (suit.isRed ? "Red King" : "Black King") : rank.name) + " of " + suit.name
        } else {
            base = rank.name
        }
        return "\(base), \(ScoreFormat.spoken(value))"
    }

    /// The sum of a hand (PRD §2.2: "the sum of their remaining cards").
    static func handValue(_ cards: [PlayingCard]) -> Int { cards.reduce(0) { $0 + $1.value } }
}

/// A card face: rank and suit in the corners, the suit large in the middle. Real cards are white
/// in every appearance.
struct PlayingCardView: View {
    let card: PlayingCard
    var width: CGFloat = 54
    var showsValue = false

    private var ink: Color { card.isRed ? Color(red: 0.84, green: 0.13, blue: 0.2) : Color(red: 0.08, green: 0.08, blue: 0.1) }

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: width * 0.12)
                .fill(.white)
                .overlay {
                    RoundedRectangle(cornerRadius: width * 0.12).strokeBorder(.black.opacity(0.15))
                }
                .overlay(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        Text(card.rank.symbol).font(.system(size: width * 0.26, weight: .bold, design: .serif))
                        if let suit = card.suit { Text(suit.rawValue).font(.system(size: width * 0.2)) }
                    }
                    .foregroundStyle(ink)
                    .padding(width * 0.08)
                }
                .overlay {
                    Text(card.suit?.rawValue ?? "JOKER")
                        .font(card.suit == nil ? .system(size: width * 0.17, weight: .heavy) : .system(size: width * 0.5))
                        .foregroundStyle(card.suit == nil ? Color.kedroRedDeep : ink)
                        .rotationEffect(card.suit == nil ? .degrees(-30) : .zero)
                        .offset(y: width * 0.08)
                }
                .frame(width: width, height: width * 1.4)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            if showsValue {
                Text(ScoreFormat.string(card.value))
                    .kedroFont(.headline)
                    .foregroundStyle(.cream)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.spokenName)
    }
}

/// A player's cards, face up, with their total.
struct HandView: View {
    let name: String
    let cards: [PlayingCard]
    var isKnocker = false
    /// The knocker went out with all four cards (an inherent knock).
    var wentOut = false
    var showsTotal = true
    var cardWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.uppercased()).kedroFont(.headline).foregroundStyle(.cream)
                if isKnocker {
                    Label(wentOut ? "went out" : "knocked", systemImage: "hand.raised.fill")
                        .font(.caption)
                        .foregroundStyle(.kedroRed)
                }
            }
            .frame(width: 76, alignment: .leading)
            if cards.isEmpty {
                Text("No cards left").font(.callout).foregroundStyle(.silverDim)
            } else {
                HStack(spacing: -cardWidth * 0.25) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                        PlayingCardView(card: card, width: cardWidth)
                    }
                }
            }
            Spacer(minLength: 4)
            if showsTotal {
                Text(ScoreFormat.string(PlayingCard.handValue(cards)))
                    .kedroFont(.score)
                    .foregroundStyle(.cream)
                    .accessibilityLabel("Hand \(ScoreFormat.spoken(PlayingCard.handValue(cards)))")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Cards") {
    VStack(spacing: 20) {
        HStack {
            PlayingCardView(card: .card(.ace, .spades), showsValue: true)
            PlayingCardView(card: .card(.number(7), .hearts), showsValue: true)
            PlayingCardView(card: .card(.king, .diamonds), showsValue: true)
            PlayingCardView(card: .card(.king, .clubs), showsValue: true)
            PlayingCardView(card: .joker, showsValue: true)
        }
        HandView(name: "Ana", cards: [.card(.ace, .spades), .card(.number(2), .clubs), .card(.king, .hearts)], isKnocker: true)
    }
    .padding()
    .background(.night)
    .preferredColorScheme(.dark)
}
