import SwiftUI

/// The standings (design §6.1 item 4, §6.2): rank, avatar with the D chip and the leader's K, name
/// and LEADING, the title under the name, and on the right the total with the last round's delta.
/// 6–8 players get compact rows; AX sizes stack the score under the name.
struct StandingsView: View {
    let state: GameState
    var mySeat: SeatID?
    /// Hides last-round deltas (self-report values before the shared reveal).
    var hidesDeltas = false
    /// A seat left out of the list because it's pinned elsewhere (your row at AX2+, design §6.2).
    var excluding: SeatID?
    var onDealerTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let compactThreshold = 6

    var body: some View {
        let compact = state.seats.count >= Self.compactThreshold
        let rows = state.standings.filter { $0.id != excluding }
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, standing in
                if index > 0 { Divider().overlay(.rule) }
                StandingRow(
                    standing: standing,
                    isMe: standing.id == mySeat,
                    compact: compact,
                    hidesDelta: hidesDeltas,
                    showsLeader: !state.rounds.isEmpty,
                    onDealerTap: onDealerTap
                )
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15), value: state.standings.map(\.id))
    }
}

/// One standings row. Read by VoiceOver as one element ("Ana, 2nd place, 29 points, last round plus 9").
struct StandingRow: View {
    let standing: Standing
    var isMe = false
    var compact = false
    var hidesDelta = false
    var showsLeader = true
    var onDealerTap: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.tableInsights) private var insights
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        HStack(alignment: stacked ? .top : .center, spacing: compact ? 10 : 12) {
            Text(standing.rank.label)
                .kedroFont(compact ? .scoreCompact : .headline)
                .foregroundStyle(isLeading ? Color.gold : Color.silver)
                .frame(minWidth: 22)
            avatar
            if stacked {
                VStack(alignment: .leading, spacing: 4) {
                    nameBlock
                    HStack(spacing: 8) {
                        score
                        delta
                    }
                }
                Spacer(minLength: 0)
            } else {
                nameBlock
                Spacer(minLength: 8)
                if compact {
                    HStack(spacing: 8) {
                        delta
                        score
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 3) {
                        score
                        delta
                    }
                }
            }
        }
        .padding(.vertical, compact ? 6 : 9)
        .padding(.horizontal, 4)
        .frame(minHeight: compact ? 54 : 62)
        .background {
            if isMe {
                RoundedRectangle(cornerRadius: 12).fill(Color.kedroRed.opacity(0.06))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityActions {
            if let onDealerTap, standing.isDealer {
                Button(TableText.text("button.changeDealer"), action: onDealerTap)
            }
        }
    }

    private var isLeading: Bool { showsLeader && standing.isLeader }

    private var avatar: some View {
        AvatarView(
            seat: standing.seat,
            size: compact ? .compact : .standings,
            isLeader: isLeading,
            isDealer: standing.isDealer,
            ring: isLeading ? .winner : .none
        )
        .contentShape(.circle)
        .onTapGesture {
            if standing.isDealer { onDealerTap?() }
        }
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(standing.seat.displayName)
                    .kedroFont(.headline)
                    .foregroundStyle(.cream)
                    .lineLimit(1)
                if isLeading {
                    Text(Literal.text("label.leading"))
                        .kedroFont(.label)
                        .foregroundStyle(.gold)
                }
            }
            if let subtitle {
                subtitle
            }
        }
    }

    /// Guest caption, or the title (TI-xx in the viewer's level) with "· 4 OF 5" while unranked.
    private var subtitle: Text? {
        let seat = standing.seat
        if seat.isGuest {
            return Text(Literal.text("label.guest")).font(.footnote).foregroundStyle(.silverDim)
        }
        guard let titleID = insights.titleID(seat) else { return nil }
        let title = Text(app.voice.line(titleID).uppercased())
            .font(.kedro(.label))
            .foregroundStyle(.kedroRed)
        if let games = seat.gamesPlayed, games < 5 {
            let meter = Text(" · " + Literal.text("label.meter", ["n": games]).uppercased())
                .font(.kedro(.label))
                .foregroundStyle(.silverDim)
            return Text("\(title)\(meter)")
        }
        return title
    }

    private var score: some View {
        ScoreText(value: standing.total, style: compact ? .scoreCompact : .score)
            .foregroundStyle(isLeading ? Color.gold : Color.cream)
    }

    @ViewBuilder
    private var delta: some View {
        if let last = standing.lastRound, !hidesDelta {
            if let outcome = last.outcome {
                HStack(spacing: 4) {
                    OutcomeBadge(outcome: outcome)
                    Text(Self.knockMath(outcome, hand: last.hand))
                        .font(.caption)
                        .foregroundStyle(.silver)
                }
                .fixedSize()
            } else {
                Text(ScoreFormat.signed(last.score))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.silver)
            }
        }
    }

    /// The number after the outcome badge: "−10", "5", "2 + 10" (the badge carries the word).
    static func knockMath(_ outcome: KnockOutcome, hand: Int) -> String {
        switch outcome {
        case .landed: ScoreFormat.string(Scoring.landedScore)
        case .tied: ScoreFormat.string(hand)
        case .failed: "\(ScoreFormat.string(hand)) + \(Scoring.failedPenalty)"
        }
    }

    private var accessibilityText: String {
        var parts = [standing.seat.displayName]
        if standing.seat.isGuest { parts.append("guest") }
        parts.append("\(standing.rank.ordinal) place" + (standing.rank.isShared ? ", tied" : ""))
        parts.append("\(ScoreFormat.spoken(standing.total)) points")
        if isLeading { parts.append("leading") }
        if standing.isDealer { parts.append("dealer") }
        if let last = standing.lastRound, !hidesDelta {
            if let outcome = last.outcome {
                parts.append("knocked, \(outcome.word), \(Self.knockMath(outcome, hand: last.hand).replacingOccurrences(of: ScoreFormat.minus, with: "minus "))")
            } else {
                parts.append("last round " + (last.score > 0 ? "plus \(last.score)" : ScoreFormat.spoken(last.score)))
            }
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("5 players") {
    ScrollView {
        StandingsView(state: PreviewData.sampleState(throughRound: 5), mySeat: PreviewData.noahSeat)
            .padding()
    }
    .background(.night)
    .previewEnvironment()
}

#Preview("8 players, compact") {
    StandingsView(state: TablePreviews.eightPlayerState, mySeat: PreviewData.noahSeat)
        .padding()
        .background(.night)
        .previewEnvironment()
}
