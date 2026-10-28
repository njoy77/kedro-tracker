import SwiftUI

/// The primary action: a kedroRed capsule, white label (Record Round, Deal, Sit Down, Run It Back).
/// Pressed: kedroRedDeep. One per screen.
struct KedroPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(configuration.isPressed ? Color.kedroRedDeep : Color.kedroRed, in: .capsule)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.capsule)
    }
}

/// Secondary actions on glass (Knock, Talk, toolbar buttons). Liquid Glass, falling back to
/// `surfaceRaised` with Reduce Transparency. Glass is only ever for controls (design §3.3).
struct KedroGlassButtonStyle: ButtonStyle {
    /// Fill the available width (true) or hug the label (false, e.g. the 64 pt Knock button).
    var expands = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .headline) private var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.headline)
            .foregroundStyle(.cream)
            .padding(.horizontal, 18)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: height)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.capsule)
        if reduceTransparency {
            label
                .background(.surfaceRaised, in: .capsule)
                .overlay { Capsule().strokeBorder(.rule) }
                .opacity(configuration.isPressed ? 0.7 : 1)
        } else {
            label
                .glassEffect(.regular.interactive(), in: .capsule)
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

extension ButtonStyle where Self == KedroPrimaryButtonStyle {
    static var kedroPrimary: KedroPrimaryButtonStyle { KedroPrimaryButtonStyle() }
}

extension ButtonStyle where Self == KedroGlassButtonStyle {
    static var kedroGlass: KedroGlassButtonStyle { KedroGlassButtonStyle() }
    static var kedroGlassWide: KedroGlassButtonStyle { KedroGlassButtonStyle(expands: true) }
}

extension View {
    /// A glass background for non-button chrome (bars, pills), with the Reduce Transparency fallback.
    func kedroGlassBackground<S: Shape>(in shape: S) -> some View {
        modifier(GlassBackground(shape: shape))
    }
}

private struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.surfaceRaised, in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

#Preview("Buttons") {
    VStack(spacing: 16) {
        Button("Record Round 6") {}
            .buttonStyle(.kedroPrimary)
        Button("Deal") {}
            .buttonStyle(.kedroPrimary)
            .disabled(true)
        HStack(spacing: 10) {
            Button("Knock", systemImage: "hand.raised") {}
                .labelStyle(.iconOnly)
                .buttonStyle(.kedroGlass)
            Button("Record Round 6") {}
                .buttonStyle(.kedroPrimary)
            Button("Talk", systemImage: "bubble.left.and.text.bubble.right") {}
                .labelStyle(.iconOnly)
                .buttonStyle(.kedroGlass)
        }
        Button("Join with Code") {}
            .buttonStyle(.kedroGlassWide)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.night)
    .preferredColorScheme(.dark)
}
