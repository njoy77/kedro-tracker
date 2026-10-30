import SwiftUI

/// The custom number pad (design §7.1): 1–9, −, 0, ⌫. Keys are a third of the width and 56 pt
/// tall (72 pt at accessibility sizes), with a selection haptic. Not the system keyboard, so it has
/// the − key Cambio needs and no upper limit.
struct NumberPad: View {
    let onKey: (PadKey) -> Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var taps = 0
    @State private var refusals = 0

    var body: some View {
        let height: CGFloat = dynamicTypeSize.isAccessibilitySize ? 72 : 56
        Grid(horizontalSpacing: 7, verticalSpacing: 7) {
            ForEach(PadKey.layout, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button {
                            if onKey(key) { taps += 1 } else { refusals += 1 }
                        } label: {
                            Text(key.label)
                                .kedroFont(.pad)
                                .foregroundStyle(isFunction(key) ? Color.silver : Color.cream)
                                .frame(maxWidth: .infinity, minHeight: height)
                                .background(.surfaceRaised, in: .rect(cornerRadius: 14))
                                .contentShape(.rect(cornerRadius: 14))
                        }
                        .buttonStyle(PadKeyStyle())
                        .accessibilityLabel(key.accessibilityLabel)
                        .buttonRepeatBehavior(key == .delete ? .enabled : .automatic)
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: taps)
        .sensoryFeedback(.warning, trigger: refusals)
    }

    private func isFunction(_ key: PadKey) -> Bool {
        if case .digit = key { false } else { true }
    }
}

/// Dims a pad key while pressed.
struct PadKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Card mode (design §7.3): `A 2 3 4 5 / 6 7 8 9 10 / J Q K♠♣ K♥♦ Joker` as minimal card faces,
/// red Kings marked −1. The red King key disables after two in one round and says why.
struct CardPalette: View {
    /// Red Kings still available to this hand.
    let redKingsLeft: Int
    let onCard: (CardFace) -> Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var taps = 0

    private static let rows: [[CardFace]] = [
        [.ace, .two, .three, .four, .five],
        [.six, .seven, .eight, .nine, .ten],
        [.jack, .queen, .blackKing, .redKing, .joker],
    ]

    var body: some View {
        let height: CGFloat = dynamicTypeSize.isAccessibilitySize ? 72 : 58
        VStack(spacing: 6) {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(Self.rows, id: \.self) { row in
                    GridRow {
                        ForEach(row) { card in
                            Button {
                                if onCard(card) { taps += 1 }
                            } label: {
                                CardFaceView(card: card, height: height)
                            }
                            .buttonStyle(PadKeyStyle())
                            .disabled(card.isRed && redKingsLeft <= 0)
                            .accessibilityLabel(card.accessibilityLabel)
                        }
                    }
                }
            }
            if redKingsLeft <= 0 {
                Text(TableText.text("label.redKingsOut"))
                    .font(.caption)
                    .foregroundStyle(.silver)
            }
        }
        .sensoryFeedback(.selection, trigger: taps)
    }
}

/// A minimal card face for the palette.
struct CardFaceView: View {
    let card: CardFace
    var height: CGFloat = 58

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 1) {
            Text(card.paletteLabel)
                .font(.system(card == .joker ? .subheadline : .title3, design: .rounded, weight: .semibold))
                .foregroundStyle(card.isRed ? Color.kedroRed : Color.cream)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if card.isRed {
                Text(ScoreFormat.string(card.value))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.kedroRed)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .background(.surfaceRaised, in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.rule) }
        .opacity(isEnabled ? 1 : 0.35)
        .contentShape(.rect(cornerRadius: 10))
    }
}

#Preview("Pad") {
    NumberPad { _ in true }
        .padding()
        .background(.surface)
        .previewEnvironment()
}

#Preview("Cards") {
    VStack(spacing: 24) {
        CardPalette(redKingsLeft: 2) { _ in true }
        CardPalette(redKingsLeft: 0) { _ in true }
    }
    .padding()
    .background(.surface)
    .previewEnvironment()
}
