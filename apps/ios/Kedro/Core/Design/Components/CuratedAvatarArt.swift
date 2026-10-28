import SwiftUI

/// Line art for the 24 curated avatars, drawn on a 48 × 48 grid in the mockups' inked style.
///
/// TODO(design §18.2): these are placeholders for the commissioned illustrations in the logo's
/// gritty, hand-inked style. Swap in asset-catalog art per `CuratedAvatarID` when it arrives
/// (keep the IDs; they're stored in player profiles).
struct CuratedAvatarArt: View {
    let id: CuratedAvatarID

    var body: some View {
        Canvas { context, size in
            let glyph = CuratedGlyph.glyph(for: id)
            let scale = min(size.width, size.height) / 48
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            for stroke in glyph.strokes {
                context.stroke(
                    SVGPath.path(stroke.data).applying(transform),
                    with: .foreground,
                    style: StrokeStyle(lineWidth: stroke.width * scale, lineCap: .round, lineJoin: .round)
                )
            }
            for fill in glyph.fills {
                context.fill(SVGPath.path(fill).applying(transform), with: .foreground)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// One avatar's drawing: stroked and filled SVG path data on a 48 × 48 grid.
struct CuratedGlyph {
    struct Stroke {
        var data: String
        var width: Double = 1.8
    }

    var strokes: [Stroke]
    var fills: [String] = []

    private static func s(_ data: String, _ width: Double = 1.8) -> Stroke { Stroke(data: data, width: width) }
    private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> String { SVGPath.circle(cx, cy, r) }

    static func glyph(for id: CuratedAvatarID) -> CuratedGlyph {
        switch id {
        // The first twelve are the mockups' drawings (docs/design/mockups.html).
        case .horse:
            CuratedGlyph(strokes: [s("M14 44c1-8 3-13 7-17-3 0-6-1-8-3 3-1 6-1 9-3l3-9c1-3 4-5 7-5l2-4 1 4c3 1 5 4 6 7l-2 2c-1-1-3-1-4 0l1 6c1 6-1 11-5 15l-1 7z")],
                         fills: [circle(31, 13, 1.2)])
        case .joker:
            CuratedGlyph(strokes: [s("M8 30 14 10l8 13 2-17 2 17 8-13 6 20z"), s("M8 30h32v6H8z")],
                         fills: [circle(14, 9, 2.4), circle(24, 5, 2.4), circle(34, 9, 2.4)])
        case .skull:
            CuratedGlyph(strokes: [s("M10 22a14 14 0 0 1 28 0c0 5-2 8-5 10v6H15v-6c-3-2-5-5-5-10z"), s("M19 38v4M24 38v4M29 38v4", 1.6)],
                         fills: [circle(18, 23, 3.6), circle(30, 23, 3.6), "M24 28l-2 4h4z"])
        case .crown:
            CuratedGlyph(strokes: [s("M7 34 9 14l9 9 6-13 6 13 9-9 2 20z"), s("M7 38h34")])
        case .dice:
            CuratedGlyph(strokes: [s(SVGPath.rect(9, 9, 30, 30, radius: 6))],
                         fills: [circle(17, 17, 2.4), circle(24, 24, 2.4), circle(31, 31, 2.4)])
        case .glass:
            CuratedGlyph(strokes: [s("M11 10h26l-3 30H14z"), s("M13 24h22", 1.4), s("M18.69 26.44L25.54 27.9L24.08 34.74L17.23 33.29Z", 1.3)])
        case .ghost:
            CuratedGlyph(strokes: [s("M11 42V22a13 13 0 0 1 26 0v20l-4.3-4-4.4 4-4.3-4-4.3 4-4.4-4z")],
                         fills: [circle(19, 22, 2.4), circle(29, 22, 2.4)])
        case .crow:
            CuratedGlyph(strokes: [s("M6 28c6-1 10-6 14-12 3-4 8-5 11-3l7-1-5 4c2 5 0 11-5 15l-3 9-2-7c-6 1-12 0-17-5z")],
                         fills: [circle(31, 17, 1.3)])
        case .bull:
            CuratedGlyph(strokes: [s("M8 12c2 6 6 8 10 8M40 12c-2 6-6 8-10 8"), s("M16 20h16l-1 12c-1 5-4 8-7 8s-6-3-7-8z"), s(SVGPath.ellipse(24, 35, 4, 2.4), 1.4)],
                         fills: [circle(20, 26, 1.6), circle(28, 26, 1.6)])
        case .eye:
            CuratedGlyph(strokes: [s("M5 24c5-8 12-12 19-12s14 4 19 12c-5 8-12 12-19 12S10 32 5 24z")],
                         fills: [circle(24, 24, 6)])
        case .flame:
            CuratedGlyph(strokes: [s("M24 4c2 8 12 12 12 24a12 12 0 0 1-24 0c0-6 3-9 5-12 0 4 2 6 4 7-1-7 1-13 3-19z")])
        case .spade:
            CuratedGlyph(strokes: [s("M24 6C18 14 9 19 9 27a7.5 7.5 0 0 0 13 5l-3 10h10l-3-10a7.5 7.5 0 0 0 13-5c0-8-9-13-15-21z")])
        // The rest follow the same hand.
        case .wolf:
            CuratedGlyph(strokes: [s("M10 8l6 10h16l6-10 2 16c0 8-6 14-16 18C14 38 8 32 8 24z"), s("M20 36l4 3 4-3", 1.4)],
                         fills: ["M15 25l6 1.5-6 2z", "M33 25l-6 1.5 6 2z", circle(24, 33, 1.8)])
        case .shark:
            CuratedGlyph(strokes: [s("M10 34C16 30 20 20 22 8c6 8 12 18 16 26z"), s("M4 40c3-2.5 6-2.5 9 0s6 2.5 9 0 6-2.5 9 0 6 2.5 9 0", 1.6)])
        case .hustler:
            CuratedGlyph(strokes: [s("M6 32c6 3 30 3 36 0"), s("M13 31l3-15c1-3 4-4 8-2 4-2 7-1 8 2l3 15"), s("M14.2 25h19.6", 1.4), s("M24 14v4", 1.4)])
        case .ace:
            CuratedGlyph(strokes: [s(SVGPath.rect(12, 6, 24, 36, radius: 4)), s("M18 32l6-16 6 16M20.4 26h7.2")])
        case .redKing:
            CuratedGlyph(strokes: [s(SVGPath.rect(12, 6, 24, 36, radius: 4)), s("M17 28l1-10 4 4 2-6 2 6 4-4 1 10z"), s("M19 33h10", 1.4)],
                         fills: [circle(24, 11, 1.3)])
        case .lastCall:
            CuratedGlyph(strokes: [s("M10 10h28L24 26z"), s("M24 26v14M17 40h14"), s("M21 15l-5-7", 1.3)],
                         fills: [circle(21, 15, 2)])
        case .ashtray:
            CuratedGlyph(strokes: [s(SVGPath.ellipse(24, 30, 16, 6)), s("M8 30v4c0 3 7 6 16 6s16-3 16-6v-4"), s("M26 27l12-10", 2.4), s("M40 13c-2-2 1-4-1-6", 1.4)])
        case .hourglass:
            CuratedGlyph(strokes: [s("M12 6h24M12 42h24"), s("M15 6c0 10 9 13 9 18s-9 8-9 18M33 6c0 10-9 13-9 18s9 8 9 18")],
                         fills: ["M18.5 39c1-4 4-6 5.5-7.5 1.5 1.5 4.5 3.5 5.5 7.5z"])
        case .cardsFan:
            CuratedGlyph(strokes: [s("M9 15l9-3 7 26-9 3z", 1.6), s("M19 9h10v28H19z", 1.6), s("M30 12l9 3-7 26-9-3z", 1.6)],
                         fills: [circle(24, 18, 1.8)])
        case .horseshoe:
            CuratedGlyph(strokes: [s("M14 8v14c0 9 4.5 16 10 16s10-7 10-16V8"), s("M19 8v14c0 6 2.2 11 5 11s5-5 5-11V8"), s("M14 8h5M29 8h5")],
                         fills: [circle(16.5, 14, 1), circle(16.5, 22, 1), circle(31.5, 14, 1), circle(31.5, 22, 1)])
        case .dagger:
            CuratedGlyph(strokes: [s("M24 4l4 7v19h-8V11z"), s("M14 30h20"), s("M22 30v9h4v-9")],
                         fills: [circle(24, 42, 2.2)])
        case .moon:
            CuratedGlyph(strokes: [s("M30 6a18 18 0 1 0 12 26A14 14 0 1 1 30 6z")],
                         fills: [circle(38, 12, 1.2), circle(42, 20, 0.9)])
        }
    }
}

#Preview("Curated avatars") {
    ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
            ForEach(CuratedAvatarID.allCases) { id in
                VStack {
                    AvatarView(avatar: .curated(id), name: id.displayName, size: .medium)
                        .opacity(id.isSecret ? 0.35 : 1)
                    Text(id.displayName).font(.caption2).foregroundStyle(.silver)
                }
            }
        }
        .padding()
    }
    .background(.night)
    .preferredColorScheme(.dark)
}
