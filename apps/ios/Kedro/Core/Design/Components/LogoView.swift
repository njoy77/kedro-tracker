import SwiftUI

/// The full Kedro logo (design §3.1): the red script over the silver horse. The brand.
///
/// Never recolored, cropped differently, or animated beyond a single fade/scale. Always on a dark
/// surface; minimum width 160 pt. The artwork's transparent margins are trimmed so `width` is the
/// visible width (same crop as the mockups).
struct LogoView: View {
    static let minimumWidth: CGFloat = 160
    /// Visible artwork aspect ratio (width / height) after trimming.
    static let aspectRatio: CGFloat = 910 / 515

    var width: CGFloat = 300

    var body: some View {
        let visibleWidth = max(width, Self.minimumWidth)
        Image(.logo)
            .resizable()
            .interpolation(.high)
            .frame(width: visibleWidth * 1.1253, height: visibleWidth * 1.1253)
            .offset(x: -visibleWidth * 0.0659, y: -visibleWidth * 0.1923)
            .frame(width: visibleWidth, height: visibleWidth / Self.aspectRatio, alignment: .topLeading)
            .clipped()
            .accessibilityElement()
            .accessibilityLabel("Kedro")
            .accessibilityAddTraits(.isImage)
    }
}

/// The small mark (design §3.2, option A): the script "K" from the wordmark. Used for the leader
/// badge, badges, the mini bar, the Table card and anywhere the full logo can't fit.
///
/// TODO(design §18.1): replace the raster crop with the commissioned vector K so `.tinted`
/// renders a clean single-color mark (today the silver drop shadow tints too).
struct KMark: View {
    enum Style {
        /// The artwork's own colors (red K, silver shadow).
        case original
        /// A single color (template rendering), e.g. gold for the leader badge.
        case tinted(Color)
    }

    /// Mark aspect ratio (width / height).
    static let aspectRatio: CGFloat = 275 / 410

    var height: CGFloat = 22
    var style: Style = .original

    var body: some View {
        Group {
            switch style {
            case .original:
                Image(.kMark).resizable()
            case .tinted(let color):
                Image(.kMark).resizable().renderingMode(.template).foregroundStyle(color)
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

#Preview("Logo and mark") {
    VStack(spacing: 32) {
        LogoView(width: 300)
        LogoView(width: 160)
        HStack(spacing: 24) {
            KMark(height: 44)
            KMark(height: 22)
            KMark(height: 14, style: .tinted(.gold))
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.nightGradient)
    .preferredColorScheme(.dark)
}
