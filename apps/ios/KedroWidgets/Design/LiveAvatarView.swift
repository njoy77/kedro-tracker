import SwiftUI
import WidgetKit

/// A small avatar for widgets and the Live Activity (design §3.5: 20 pt in the Live Activity).
/// Emoji on their palette color, curated line art on its dark tile, guests as an initial with a
/// dashed silver ring. Photos arrive as initials (the extension has no network).
struct LiveAvatarView: View {
    let avatar: LiveAvatar
    var size: CGFloat = 20

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(.circle)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch avatar {
        case .emoji(let emoji, let colorIndex):
            Circle()
                .fill(AvatarPalette.color(colorIndex))
                .overlay {
                    Text(emoji).font(.system(size: size * 0.58))
                }
        case .curated(let id):
            Circle()
                .fill(CuratedTile.background)
                .overlay {
                    if let curated = CuratedAvatarID(rawValue: id) {
                        CuratedAvatarArt(id: curated)
                            .foregroundStyle(CuratedTile.ink)
                            .padding(size * 0.12)
                    }
                }
                .overlay(Circle().strokeBorder(CuratedTile.edge, lineWidth: 1))
        case .initial(let letter, let isGuest):
            Circle()
                .fill(Color.surfaceRaised)
                .overlay {
                    Text(letter)
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.silver)
                }
                .overlay {
                    if isGuest {
                        Circle().strokeBorder(Color.silver, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
        }
    }
}

/// The dealer's "D" chip (design §6.4).
struct DealerChip: View {
    var size: CGFloat = 12

    var body: some View {
        Text("D")
            .font(.system(size: size * 0.62, weight: .bold))
            .foregroundStyle(.night)
            .frame(width: size, height: size)
            .background(.cream, in: .circle)
            .accessibilityHidden(true)
    }
}

/// A knock outcome glyph with its math ("✓ −10", "✗ 2 + 10"), never color alone (design §3.6).
struct LiveDeltaText: View {
    let delta: String?
    let outcome: LiveKnockOutcome?

    var body: some View {
        HStack(spacing: 2) {
            if let outcome {
                Image(systemName: outcome.systemImage)
                    .font(.system(size: 9, weight: .heavy))
            }
            if let delta {
                Text(delta)
                    .monospacedDigit()
            }
        }
        .font(.caption2)
        .foregroundStyle(.silver)
        .lineLimit(1)
    }
}

#Preview("Avatars and chips") {
    VStack(spacing: 12) {
        HStack {
            LiveAvatarView(avatar: .emoji(emoji: "🦊", colorIndex: 0), size: 32)
            LiveAvatarView(avatar: .curated(id: "bull"), size: 32)
            LiveAvatarView(avatar: .initial(letter: "S", isGuest: true), size: 32)
        }
        HStack {
            DealerChip()
            LiveDeltaText(delta: "2 + 10", outcome: .failed)
            LiveDeltaText(delta: "+9", outcome: nil)
        }
    }
    .padding()
    .background(.night)
}

