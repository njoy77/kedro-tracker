import SwiftUI

/// Kedro's text styles (design §3.4). Bebas Neue for scores and headlines, SF Pro for anything
/// you read. Every style scales with Dynamic Type.
///
/// Apply with `.kedroFont(.score)` (which also sets tracking, tabular digits and italics), or
/// use `Font.kedro(.headline)` inside `Text` concatenation.
///
/// Bebas is all caps by design: pass names in real casing and uppercase them for display with
/// `.textCase(.uppercase)` or `.kedroFont`, so VoiceOver still reads "Noah", not "N-O-A-H".
enum KedroTextStyle: Sendable {
    /// Cumulative scores, ranks, ratings. Bebas 34, tabular digits.
    case score
    /// Scores in compact (6–8 player) rows. Bebas 28.
    case scoreCompact
    /// Display mode standings. Bebas 64.
    case scoreLarge
    /// Screen heroes: winner name, "ROUND 5 OF 8", leaderboard rank. Bebas 40.
    case display
    /// Section headers, player names in standings. Bebas 22.
    case headline
    /// Metadata line, LEADING tag, column heads. Bebas 13, tracked +4%.
    case label
    /// The voice line under a fact. SF Pro italic, callout.
    case roast
    /// Number pad keys. SF Pro Rounded semibold 30, monospaced digits.
    case pad

    static let bebas = "BebasNeue-Regular"

    var size: CGFloat {
        switch self {
        case .score: 34
        case .scoreCompact: 28
        case .scoreLarge: 64
        case .display: 40
        case .headline: 22
        case .label: 13
        case .roast: 16
        case .pad: 30
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .score, .scoreLarge, .display: .largeTitle
        case .scoreCompact: .title
        case .headline: .title2
        case .label: .footnote
        case .roast: .callout
        case .pad: .title
        }
    }

    var isBebas: Bool {
        switch self {
        case .roast, .pad: false
        default: true
        }
    }

    /// Tracking as a fraction of the point size.
    var trackingFactor: CGFloat {
        switch self {
        case .label: 0.04
        case .headline, .display: 0.02
        default: 0
        }
    }

    var usesTabularDigits: Bool {
        switch self {
        case .score, .scoreCompact, .scoreLarge, .pad, .display: true
        default: false
        }
    }
}

extension Font {
    /// A Kedro text style as a font. Scales with Dynamic Type. Prefer `.kedroFont(_:)`, which
    /// also applies tracking and digits.
    static func kedro(_ style: KedroTextStyle) -> Font {
        switch style {
        case .roast:
            .callout.italic()
        case .pad:
            .system(style.textStyle, design: .rounded, weight: .semibold).monospacedDigit()
        default:
            .custom(KedroTextStyle.bebas, size: style.size, relativeTo: style.textStyle)
        }
    }
}

private struct KedroFontModifier: ViewModifier {
    let style: KedroTextStyle
    @ScaledMetric private var padSize: CGFloat
    @ScaledMetric private var trackingBase: CGFloat

    init(style: KedroTextStyle) {
        self.style = style
        _padSize = ScaledMetric(wrappedValue: KedroTextStyle.pad.size, relativeTo: .title)
        _trackingBase = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        let font: Font = style == .pad
            ? .system(size: padSize, weight: .semibold, design: .rounded)
            : .kedro(style)
        content
            .font(style.usesTabularDigits ? font.monospacedDigit() : font)
            .tracking(trackingBase * style.trackingFactor)
            .textCase(style.isBebas ? .uppercase : nil)
    }
}

extension View {
    /// Applies a Kedro text style: font, tracking, tabular digits, and uppercase for Bebas.
    func kedroFont(_ style: KedroTextStyle) -> some View {
        modifier(KedroFontModifier(style: style))
    }
}

#Preview("Type") {
    VStack(alignment: .leading, spacing: 10) {
        Text("26").kedroFont(.score)
        Text("45").kedroFont(.scoreCompact)
        Text("Round 5 of 8").kedroFont(.display)
        Text("Noah").kedroFont(.headline)
        Text("Round 6 of 8 · Cold Deck").kedroFont(.label).foregroundStyle(.silver)
        Text("Noah knocked on 2 and nobody had shit.").kedroFont(.roast).foregroundStyle(.silver)
        Text("1 2 3 −").kedroFont(.pad)
    }
    .foregroundStyle(.cream)
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(.night)
}
