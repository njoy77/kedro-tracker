import SwiftUI

/// Large, faint card-suit texture from the web app (design §3.1): Play, game end, welcome and
/// display mode. 2–5% opacity, never behind numbers, hidden with Reduce Transparency.
/// Place it in a `.background` so it never takes layout space or touches.
struct SuitWatermark: View {
    struct Mark: Hashable {
        var suit: String
        /// Position as a fraction of the container (0…1), for the glyph's center.
        var x: CGFloat
        var y: CGFloat
        /// Size as a fraction of the container width.
        var scale: CGFloat
        var isRed: Bool
        var opacity: Double
    }

    var marks: [Mark] = SuitWatermark.welcome

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            if !reduceTransparency {
                ForEach(marks, id: \.self) { mark in
                    Text(mark.suit)
                        .font(.system(size: proxy.size.width * mark.scale, design: .serif))
                        .foregroundStyle(mark.isRed ? Color.kedroRed : Color.cream)
                        .opacity(mark.opacity)
                        .position(x: proxy.size.width * mark.x, y: proxy.size.height * mark.y)
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Mockup frame 1: ♠ top left, ♥ right, ♦ bottom left.
    static let welcome: [Mark] = [
        Mark(suit: "♠", x: 0.2, y: 0.3, scale: 0.76, isRed: false, opacity: 0.03),
        Mark(suit: "♥", x: 0.95, y: 0.6, scale: 0.81, isRed: true, opacity: 0.05),
        Mark(suit: "♦", x: 0.2, y: 0.85, scale: 0.64, isRed: true, opacity: 0.04),
    ]

    /// Mockup frame 4: one ♥ top right.
    static let play: [Mark] = [
        Mark(suit: "♥", x: 0.95, y: 0.18, scale: 0.66, isRed: true, opacity: 0.05),
    ]

    /// Display mode and game end: all four, spread out.
    static let table: [Mark] = [
        Mark(suit: "♠", x: 0.1, y: 0.2, scale: 0.4, isRed: false, opacity: 0.03),
        Mark(suit: "♥", x: 0.9, y: 0.25, scale: 0.42, isRed: true, opacity: 0.04),
        Mark(suit: "♦", x: 0.15, y: 0.85, scale: 0.36, isRed: true, opacity: 0.035),
        Mark(suit: "♣", x: 0.85, y: 0.85, scale: 0.38, isRed: false, opacity: 0.03),
    ]
}

#Preview("Watermark") {
    Color.clear
        .background(.nightGradient)
        .background { SuitWatermark() }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
}
