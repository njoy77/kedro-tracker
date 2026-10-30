import SwiftUI

/// The Share Results image (design §10 item 6): the full logo, the winner line and the final
/// standings. Outbound images render Clean by default, because the people in that group chat
/// didn't opt in (design §8.5).
struct ShareResultsCard: View {
    let state: GameState
    var voice = Voice(level: .clean)

    var body: some View {
        let summary = GameEndSummary(state)
        VStack(spacing: 14) {
            LogoView(width: 200)
            Text(state.config.tableWord)
                .kedroFont(.label)
                .foregroundStyle(.silver)
            if let headline = summary.headline {
                Text(headline.render(voice, gameID: state.gameID, round: state.rounds.count))
                    .kedroFont(.display)
                    .foregroundStyle(.gold)
                    .multilineTextAlignment(.center)
            }
            if let line = summary.winnerLine {
                Text(line.render(voice, gameID: state.gameID, round: state.rounds.count))
                    .kedroFont(.roast)
                    .foregroundStyle(.silver)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 6) {
                ForEach(state.standings) { standing in
                    HStack(spacing: 10) {
                        Text(standing.rank.label)
                            .kedroFont(.headline)
                            .foregroundStyle(standing.isLeader ? Color.gold : Color.silver)
                            .frame(width: 28, alignment: .leading)
                        AvatarView(seat: standing.seat, size: .compact)
                        Text(standing.seat.displayName)
                            .kedroFont(.headline)
                            .foregroundStyle(.cream)
                        Spacer()
                        Text(ScoreFormat.string(standing.total))
                            .kedroFont(.scoreCompact)
                            .foregroundStyle(standing.isLeader ? Color.gold : Color.cream)
                    }
                }
            }
            .padding(14)
            .background(Color.surface, in: .rect(cornerRadius: 18))
            Text(TableText.text("label.shareFooter"))
                .font(.caption)
                .foregroundStyle(.silverDim)
        }
        .padding(28)
        .frame(width: 400)
        .background(.nightGradient)
        .environment(\.colorScheme, .dark)
    }

    /// Renders the card at 3× for the share sheet.
    static func render(state: GameState, level: LanguageLevel = .clean) -> Image? {
        let renderer = ImageRenderer(content: ShareResultsCard(state: state, voice: Voice.house(for: state, viewer: level)))
        renderer.scale = 3
        guard let image = renderer.cgImage else { return nil }
        return Image(decorative: image, scale: 3)
    }
}

#Preview {
    ShareResultsCard(state: PreviewData.sampleState(throughRound: 8, finished: true))
}
