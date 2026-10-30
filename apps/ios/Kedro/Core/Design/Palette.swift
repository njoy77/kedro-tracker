import SwiftUI

// Color tokens (design §3.3) live in Assets.xcassets/Colors with Any (light), Dark and, for
// silver and silverDim, Increase Contrast variants. Xcode generates the symbols, so use them
// directly: `.foregroundStyle(.cream)`, `.background(.surface)`, `Color.kedroRed`.
//
// | Token          | Use                                                        |
// |----------------|------------------------------------------------------------|
// | night          | App background                                             |
// | nightGradient  | Large backgrounds behind the logo (`.nightGradient` below) |
// | surface        | Cards, rows, sheets                                        |
// | surfaceRaised  | Last-round card, Table card, toasts                        |
// | rule           | Separators                                                 |
// | cream          | Primary text (inverts in light)                            |
// | silver         | Secondary text, metadata                                   |
// | silverDim      | Tertiary text, disabled                                    |
// | kedroRed       | THE accent: primary buttons, you, focus, live state        |
// | kedroRedDeep   | Pressed state, red fills behind cream text                 |
// | gold           | Leader, winner, rank #1, earned badges (never small text on light) |
//
// Rules: red never means "bad"; no green anywhere; every number sits on a solid surface;
// outcomes are words and glyphs, not colors.

extension ShapeStyle where Self == LinearGradient {
    /// `nightGradient`: Play header, game end, display mode, splash.
    static var nightGradient: LinearGradient {
        LinearGradient(colors: [.nightGradientTop, .nightGradientBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// The 12 background colors for emoji avatars (design §3.5): dark, saturated, no pastels.
/// `Avatar.emoji(_, colorIndex:)` indexes into this.
enum AvatarPalette {
    static let colors: [Color] = [
        Color(red: 0x2B / 255, green: 0x3A / 255, blue: 0x55 / 255), // navy
        Color(red: 0x3D / 255, green: 0x2A / 255, blue: 0x4D / 255), // plum
        Color(red: 0x3A / 255, green: 0x23 / 255, blue: 0x48 / 255), // violet
        Color(red: 0x4A / 255, green: 0x2A / 255, blue: 0x1D / 255), // rust
        Color(red: 0x4A / 255, green: 0x1F / 255, blue: 0x26 / 255), // wine
        Color(red: 0x1D / 255, green: 0x3B / 255, blue: 0x4F / 255), // petrol
        Color(red: 0x4F / 255, green: 0x3B / 255, blue: 0x1D / 255), // bronze
        Color(red: 0x3B / 255, green: 0x3B / 255, blue: 0x4F / 255), // slate
        Color(red: 0x5A / 255, green: 0x2A / 255, blue: 0x3A / 255), // berry
        Color(red: 0x26 / 255, green: 0x41 / 255, blue: 0x5A / 255), // steel
        Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x33 / 255), // charcoal
        Color(red: 0x52 / 255, green: 0x33 / 255, blue: 0x24 / 255), // tobacco
    ]

    static func color(_ index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

/// Fixed colors for curated avatar tiles: they stay dark in light mode (mockup frame 7).
enum CuratedTile {
    static let background = Color(red: 0x0C / 255, green: 0x0C / 255, blue: 0x10 / 255)
    static let ink = Color(red: 0xD8 / 255, green: 0xD8 / 255, blue: 0xD8 / 255)
    static let edge = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x33 / 255)
}

#Preview("Tokens") {
    let tokens: [(String, Color)] = [
        ("night", .night), ("surface", .surface), ("surfaceRaised", .surfaceRaised), ("rule", .rule),
        ("cream", .cream), ("silver", .silver), ("silverDim", .silverDim),
        ("kedroRed", .kedroRed), ("kedroRedDeep", .kedroRedDeep), ("gold", .gold),
    ]
    return ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tokens, id: \.0) { name, color in
                HStack {
                    RoundedRectangle(cornerRadius: 8).fill(color).frame(width: 44, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.rule))
                    Text(name).foregroundStyle(.cream)
                }
            }
            HStack {
                ForEach(AvatarPalette.colors.indices, id: \.self) { index in
                    Circle().fill(AvatarPalette.color(index)).frame(width: 22)
                }
            }
        }
        .padding()
    }
    .background(.nightGradient)
}
