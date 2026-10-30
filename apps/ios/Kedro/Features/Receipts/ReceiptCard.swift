import SwiftUI

/// The share-ready receipt card (design §8.5, mockup frame 13): the full logo, the game, the RC
/// line, the round being roasted, and the two of you with your totals. Always dark, so the
/// shared image looks the same in any group chat.
///
/// Rendered on screen in the composer and the feed, and to an image with `ImageRenderer` for the
/// share sheet (`ReceiptCard.image(...)`).
struct ReceiptCard: View {
    let state: GameState
    let option: ReceiptOption
    let sender: Seat
    let rival: Seat
    let level: LanguageLevel

    static let width: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            LogoView(width: 160)
                .accessibilityLabel("Kedro")
            Text(Receipts.eyebrow(for: state))
                .kedroFont(.label)
                .foregroundStyle(.silver)
                .padding(.top, 10)
            Text(option.line(level: level))
                .font(.custom(KedroTextStyle.bebas, size: 46, relativeTo: .largeTitle))
                .textCase(.uppercase)
                .foregroundStyle(.cream)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(.top, 12)
            if let roast = Receipts.roast(for: option, in: state) {
                Text(roast)
                    .font(.footnote)
                    .foregroundStyle(.silver)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            HStack(alignment: .top, spacing: 28) {
                person(sender)
                person(rival)
            }
            .padding(.top, 18)
            Text("From \(sender.displayName) · kedro.app")
                .font(.caption2)
                .foregroundStyle(.silverDim)
                .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(width: Self.width)
        .background {
            ZStack {
                Rectangle().fill(.nightGradient)
                SuitWatermark(marks: [
                    .init(suit: "♦", x: 0.86, y: 0.12, scale: 0.6, isRed: true, opacity: 0.07),
                ])
            }
        }
        .clipShape(.rect(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(.rule) }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    private var pairBest: Int {
        min(state.standing(for: sender.id)?.total ?? 0, state.standing(for: rival.id)?.total ?? 0)
    }

    private func person(_ seat: Seat) -> some View {
        let total = state.standing(for: seat.id)?.total ?? 0
        let isAhead = total == pairBest
        return VStack(spacing: 6) {
            AvatarView(seat: seat, size: .medium, ring: isAhead ? .winner : .none)
            HStack(spacing: 6) {
                Text(seat.displayName)
                    .foregroundStyle(.cream)
                Text(ScoreFormat.string(total))
                    .foregroundStyle(isAhead ? Color.gold : Color.cream)
            }
            .font(.custom(KedroTextStyle.bebas, size: 20, relativeTo: .title3))
            .textCase(.uppercase)
            .monospacedDigit()
        }
    }

    /// The card as an image for the share sheet. `ImageRenderer` can't load remote photos, so
    /// photo avatars render as their fallback.
    static func image(state: GameState, option: ReceiptOption, sender: Seat, rival: Seat, level: LanguageLevel, scale: CGFloat) -> Image? {
        let renderer = ImageRenderer(content: ReceiptCard(state: state, option: option, sender: sender, rival: rival, level: level)
            .environment(\.dynamicTypeSize, .large))
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.cgImage.map { Image(decorative: $0, scale: scale) }
    }
}

#Preview {
    let state = PreviewData.sampleState(throughRound: 8, finished: true)
    let noah = state.seat(PreviewData.noahSeat)
    let ana = state.seat(PreviewData.anaSeat)
    if let noah, let ana, let option = Receipts.options(in: state, from: noah.id, to: ana.id).first {
        ScrollView {
            VStack(spacing: 20) {
                ReceiptCard(state: state, option: option, sender: noah, rival: ana, level: .clean)
                ReceiptCard(state: state, option: Receipts.option("RC-01", in: state, from: noah.id, to: ana.id) ?? option, sender: noah, rival: ana, level: .unhinged)
            }
            .padding()
        }
        .background(.night)
        .previewEnvironment()
    }
}
