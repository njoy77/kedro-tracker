import SwiftUI

/// The last-round card (design §6.1 items 2–3): fact, verdict with **Why?**, the roast, the
/// reactions row, and for 5 s after a save the next-deal nudge (D-01).
///
/// Math first, mouth second: VoiceOver reads the fact and verdict, then the roast as a separate,
/// skippable element.
struct LastRoundCard: View {
    let state: GameState
    let voice: Voice
    var mySeat: SeatID?
    var viewerIsLearner = false
    /// "Next deal: Ana." for the first 5 s after a save.
    var nextDealer: String?
    /// Self-report values before the shared reveal.
    var isHidden = false
    var compact = false
    var onWhy: ((Round) -> Void)?
    var onReact: ((Reaction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let record = state.lastRound {
                if isHidden {
                    Text(TableText.text("label.revealing"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.cream)
                    Text(TableText.text("label.valuesHidden"))
                        .font(.footnote)
                        .foregroundStyle(.silver)
                } else {
                    roundContent(record)
                }
            } else {
                Text(TableText.text("label.noRoundsYet", ["name": state.currentDealer.map(state.name(of:)) ?? "Someone"]))
                    .font(.callout)
                    .foregroundStyle(.silver)
            }
            if let nextDealer {
                Text(voice.line("D-01", ["name": nextDealer]))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.cream)
                    .padding(.top, 6)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.surfaceRaised, in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.06), radius: 9, y: 4)
    }

    @ViewBuilder
    private func roundContent(_ record: RoundRecord) -> some View {
        let hand = record.round.knockerHand ?? 0
        let fact = Literal.fact(record.round) { state.name(of: $0) }
        VStack(alignment: .leading, spacing: 2) {
            factText(fact)
                .font(compact ? .subheadline : .body)
                .foregroundStyle(.cream)
            if let outcome = record.outcome {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Literal.verdict(outcome, hand: hand))
                        .font((compact ? Font.subheadline : .body).weight(.semibold))
                        .foregroundStyle(.cream)
                    if let onWhy {
                        Button(TableText.text("button.why")) { onWhy(record.round) }
                            .font(.subheadline)
                            .foregroundStyle(.kedroRed)
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows how this knock was scored")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)

        if let roast = TableVoice.roast(for: record, in: state, viewer: mySeat, viewerIsLearner: viewerIsLearner) {
            Text(roast.render(voice, gameID: state.gameID, round: record.number))
                .kedroFont(.roast)
                .foregroundStyle(.silver)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let onReact, !compact {
            ReactionsRow(counts: state.reactionCounts(forRound: record.number), mine: mySeat.flatMap { state.reactions[record.number]?[$0] }, onReact: onReact)
                .padding(.top, 8)
        }
    }

    /// "**Round 5.** Noah knocked on 2." with the first sentence bold.
    private func factText(_ fact: String) -> Text {
        guard let split = fact.range(of: ". ") else { return Text(fact) }
        let head = String(fact[..<split.lowerBound]) + "."
        let rest = String(fact[split.upperBound...])
        return Text("\(Text(head).bold()) \(rest)")
    }
}

/// The 5 quick reactions with counts (design §6.1 item 3). One per player per round; tapping
/// another replaces yours.
struct ReactionsRow: View {
    let counts: [(reaction: Reaction, count: Int)]
    var mine: Reaction?
    let onReact: (Reaction) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(counts, id: \.reaction) { item in
                Button {
                    onReact(item.reaction)
                } label: {
                    HStack(spacing: 4) {
                        Text(item.reaction.emoji)
                        if item.count > 0 {
                            Text(String(item.count)).monospacedDigit()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(item.reaction == mine ? Color.cream : Color.silver)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(.surface, in: .capsule)
                    .overlay {
                        if item.reaction == mine {
                            Capsule().strokeBorder(.kedroRed, lineWidth: 1.5)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.reaction.accessibilityLabel)
                .accessibilityValue(item.count == 1 ? "1 reaction" : "\(item.count) reactions")
                .accessibilityAddTraits(item.reaction == mine ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: mine)
    }
}

#Preview("After Round 5") {
    LastRoundCard(
        state: PreviewData.sampleState(throughRound: 5),
        voice: Voice(level: .unhinged),
        mySeat: PreviewData.noahSeat,
        nextDealer: "Sam",
        onWhy: { _ in },
        onReact: { _ in }
    )
    .padding()
    .background(.night)
    .previewEnvironment()
}

#Preview("Failed knock, Clean, no rounds") {
    VStack {
        LastRoundCard(state: PreviewData.sampleState(throughRound: 3), voice: Voice(level: .clean), onWhy: { _ in }, onReact: { _ in })
        LastRoundCard(state: PreviewData.sampleState(throughRound: 0), voice: Voice(level: .clean))
        LastRoundCard(state: PreviewData.sampleState(throughRound: 4), voice: Voice(level: .clean), isHidden: true)
    }
    .padding()
    .background(.night)
    .previewEnvironment()
}
