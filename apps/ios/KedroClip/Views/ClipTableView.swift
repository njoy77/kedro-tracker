import SwiftUI

/// The live Table, read-only (design §5.8): metadata, standings, the last round's fact line or
/// the live knock, plus Report Your Hand (self-report games) and Talk (canned taunts).
struct ClipTableView: View {
    @Environment(ClipModel.self) private var model
    let state: GameState

    @State private var isReporting = false
    @State private var isTalking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.isOffline {
                    offlineBanner
                }
                standings
                statusCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { actions }
        .sheet(isPresented: $isReporting) {
            ClipReportHandSheet(roundNumber: state.nextRoundNumber)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isTalking) {
            ClipTauntSheet(state: state)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ClipBadge()
                Spacer()
                if model.mySeat == nil {
                    Text(ClipCopy.watching)
                        .kedroFont(.label)
                        .foregroundStyle(.silver)
                }
            }
            Text(metadataLine)
                .kedroFont(.label)
                .foregroundStyle(.silver)
                .padding(.top, 8)
            Text(Literal.roundOf(state.progress.currentRound, state.config.plannedRounds))
                .kedroFont(.display)
                .foregroundStyle(.cream)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// "COLD DECK · NOAH DEALS"
    private var metadataLine: String {
        guard let dealer = state.currentDealer, state.status == .active else { return state.config.tableWord }
        return Literal.deals(word: state.config.tableWord, dealer: state.name(of: dealer))
    }

    private var offlineBanner: some View {
        Label(model.voice.line("F-04", ["host": model.hostName]), systemImage: "wifi.slash")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.cream)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surfaceRaised, in: .rect(cornerRadius: 12))
    }

    private var standings: some View {
        VStack(spacing: 0) {
            ForEach(state.standings) { standing in
                ClipStandingRow(
                    standing: standing,
                    isMe: standing.id == model.mySeat,
                    hasRounds: !state.rounds.isEmpty
                )
                if standing.id != state.standings.last?.id {
                    Divider().overlay(.rule)
                }
            }
        }
        .background(.surface, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var statusCard: some View {
        if let line = statusLine {
            Text(line)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.cream)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.surfaceRaised, in: .rect(cornerRadius: 14))
        }
    }

    /// The live knock (K-23) while one is marked, else the last round's fact and verdict.
    private var statusLine: String? {
        if let knock = state.liveKnock, knock.roundNumber == state.nextRoundNumber {
            return model.voice.line("K-23", ["knocker": state.name(of: knock.knocker)])
        }
        guard let last = state.lastRound else { return nil }
        let hand = last.round.knockerHand ?? 0
        let fact = Literal.fact(last.round) { state.name(of: $0) }
        guard let outcome = last.outcome else { return fact }
        return "\(fact) \(Literal.verdict(outcome, hand: hand))"
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if model.mySeat != nil, state.config.scoringMode == .selfReport, state.status == .active {
                if model.owesHand {
                    Button(Literal.text("button.reportHand")) { isReporting = true }
                        .buttonStyle(.kedroPrimary)
                        .disabled(model.isOffline)
                } else if !state.isAwaitingFinish {
                    Text(ClipCopy.reported)
                        .font(.footnote)
                        .foregroundStyle(.silver)
                }
            }
            Button(Literal.text("button.talk")) { isTalking = true }
                .buttonStyle(.kedroGlassWide)
                .disabled(model.isOffline)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// One standings row: rank, avatar, name, total and last delta, you highlighted.
struct ClipStandingRow: View {
    let standing: Standing
    let isMe: Bool
    let hasRounds: Bool

    private var isLeader: Bool { hasRounds && standing.isLeader }

    var body: some View {
        HStack(spacing: 12) {
            Text(standing.rank.label)
                .kedroFont(.headline)
                .foregroundStyle(isLeader ? Color.gold : Color.cream)
                .frame(minWidth: 26, alignment: .leading)
            AvatarView(seat: standing.seat, size: .compact, isLeader: isLeader, isDealer: standing.isDealer)
            Text(standing.seat.displayName)
                .kedroFont(.headline)
                .foregroundStyle(.cream)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                ScoreText(value: standing.total, style: .scoreCompact)
                    .foregroundStyle(isLeader ? Color.gold : Color.cream)
                if let last = standing.lastRound {
                    Text(Literal.delta(last))
                        .font(.caption2)
                        .foregroundStyle(.silver)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            if isMe { Color.kedroRed.opacity(0.18) }
        }
        .overlay(alignment: .leading) {
            if isMe { Rectangle().fill(.kedroRed).frame(width: 3) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = ["\(standing.seat.displayName), \(standing.rank.ordinal) place, \(ScoreFormat.spoken(standing.total)) points"]
        if let last = standing.lastRound {
            parts.append("last round \(Literal.delta(last))")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Watching after Round 5") {
    ClipTableView(state: PreviewData.sampleState(throughRound: 5))
        .environment(ClipModel.preview(seated: false, throughRound: 5))
        .background(.night)
        .preferredColorScheme(.dark)
}

#Preview("Seated as Sam") {
    ClipTableView(state: PreviewData.sampleState(throughRound: 5))
        .environment(ClipModel.preview(seated: true, throughRound: 5))
        .background(.night)
        .preferredColorScheme(.dark)
}
