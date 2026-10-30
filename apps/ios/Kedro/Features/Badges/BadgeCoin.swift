import SwiftUI

/// A badge as a dark coin struck with the small mark, rimmed by tier (design §12.6):
/// silver, red or gold. Unearned coins are dimmed; unearned secrets show "?".
struct BadgeCoin: View {
    let badge: BadgeID
    var isEarned: Bool
    var size: CGFloat = 64
    /// Show the category icon on the rim.
    var showsCategory = true

    var body: some View {
        let definition = badge.definition
        let isHiddenSecret = definition.isSecret && !isEarned
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x33 / 255), Color(red: 0x0C / 255, green: 0x0C / 255, blue: 0x10 / 255)],
                    center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.6
                ))
            Circle()
                .strokeBorder(rim(isHiddenSecret ? .none : definition.tier), lineWidth: max(2.5, size * 0.055))
            if isHiddenSecret {
                Text("?")
                    .font(.custom(KedroTextStyle.bebas, fixedSize: size * 0.42))
                    .foregroundStyle(Color(white: 0.35))
            } else {
                KMark(height: size * 0.42)
                    .saturation(isEarned ? 1 : 0)
                    .opacity(isEarned ? 1 : 0.45)
            }
        }
        .frame(width: size, height: size)
        .saturation(isEarned ? 1 : 0)
        .opacity(isEarned ? 1 : 0.8)
        .overlay(alignment: .bottomTrailing) {
            if showsCategory, !isHiddenSecret, size >= 48 {
                Image(systemName: definition.category.systemImage)
                    .font(.system(size: size * 0.15, weight: .bold))
                    .foregroundStyle(isEarned ? Color.cream : Color.silverDim)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .background(Circle().fill(Color(red: 0x13 / 255, green: 0x13 / 255, blue: 0x1A / 255)))
                    .overlay { Circle().strokeBorder(rim(definition.tier), lineWidth: 1) }
                    .offset(x: 2, y: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let definition = badge.definition
        if definition.isSecret && !isEarned { return "Secret badge, not earned" }
        return "\(definition.name), \(definition.tier.name) badge, \(isEarned ? "earned" : "not earned")"
    }

    /// The tier's metal gradient (the mockup's `.coin.s/.r/.g`).
    private func rim(_ tier: BadgeTier) -> LinearGradient {
        let colors: [Color] = switch tier {
        case .silver: [Color(white: 0.94), Color(white: 0.55), Color(white: 0.85)]
        case .red: [Color(red: 1, green: 0.42, blue: 0.46), .kedroRedDeep, .kedroRed]
        case .gold: [Color(red: 1, green: 0.94, blue: 0.66), Color(red: 0.79, green: 0.61, blue: 0.11), .gold]
        case .none: [Color(white: 0.2), Color(white: 0.2)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

#Preview("Coins") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            BadgeCoin(badge: .landedIt, isEarned: true)
            BadgeCoin(badge: .hatTrick, isEarned: true)
            BadgeCoin(badge: .steadyHand, isEarned: true)
        }
        HStack(spacing: 16) {
            BadgeCoin(badge: .royalPair, isEarned: false)
            BadgeCoin(badge: .exorcism, isEarned: false)
            BadgeCoin(badge: .didTheReading, isEarned: true)
            BadgeCoin(badge: .ghostHand, isEarned: true, size: 40)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.night)
}
