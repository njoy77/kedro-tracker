import SwiftUI

/// A knock outcome as word and glyph, never color alone (design §3.6):
/// landed = solid cream, tied = outline, failed = hatched.
struct OutcomeBadge: View {
    let outcome: KnockOutcome
    /// Show the word ("landed") next to the glyph.
    var showsWord = true

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: outcome.systemImage)
                .font(.caption2.weight(.heavy))
            if showsWord {
                Text(outcome.word)
            }
        }
        .font(.caption2.weight(.bold))
        .padding(.horizontal, showsWord ? 7 : 5)
        .padding(.vertical, 2)
        .foregroundStyle(foreground)
        .background { background }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("knock \(outcome.word)")
    }

    private var foreground: Color {
        switch outcome {
        case .landed: .night
        case .tied, .noPenalty: .silver
        case .failed: .cream
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        switch outcome {
        case .landed:
            shape.fill(.cream)
        case .tied:
            shape.strokeBorder(.silver, lineWidth: 1.2)
        case .noPenalty:
            // An inherent knock someone beat: dashed, since it was never at risk of the +10.
            shape.strokeBorder(.silver, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
        case .failed:
            HatchPattern()
                .clipShape(shape)
                .overlay { shape.strokeBorder(.silver, lineWidth: 1.2) }
        }
    }
}

/// Diagonal hatching for failed knocks.
struct HatchPattern: View {
    var color: Color = .rule
    var spacing: CGFloat = 6
    var lineWidth: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width + size.height {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .accessibilityHidden(true)
    }
}

/// The step meter for players not yet ranked (design §12.4–§12.5): "3 of 10".
struct ProgressMeter: View {
    var value: Int
    var total = Ranking.gamesToRank
    /// Show "3 of 10" after the steps.
    var showsLabel = true

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { step in
                    Capsule()
                        .fill(step < value ? Color.kedroRed : Color.rule)
                        .frame(width: total > 5 ? 8 : 14, height: 5)
                }
            }
            if showsLabel {
                Text(Literal.text("label.meter", ["n": min(value, total), "total": total]))
                    .font(.caption2)
                    .foregroundStyle(.silverDim)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Games toward a rank")
        .accessibilityValue("\(min(value, total)) of \(total)")
    }
}

/// A score in Bebas with tabular digits and a true minus. Counts to new values (design §3.7).
struct ScoreText: View {
    let value: Int
    var style: KedroTextStyle = .score

    var body: some View {
        Text(ScoreFormat.string(value))
            .kedroFont(style)
            .contentTransition(.numericText(value: Double(value)))
            .animation(.smooth(duration: 0.35), value: value)
            .accessibilityLabel(ScoreFormat.spoken(value))
    }
}

#Preview("Badges, meter, scores") {
    VStack(spacing: 24) {
        HStack {
            OutcomeBadge(outcome: .landed)
            OutcomeBadge(outcome: .tied)
            OutcomeBadge(outcome: .failed)
            OutcomeBadge(outcome: .failed, showsWord: false)
        }
        ProgressMeter(value: 3)
        ProgressMeter(value: 4, showsLabel: false)
        HStack(spacing: 24) {
            ScoreText(value: 26).foregroundStyle(.gold)
            ScoreText(value: -10)
            ScoreText(value: 45, style: .scoreCompact)
        }
        .foregroundStyle(.cream)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.night)
    .preferredColorScheme(.dark)
}
