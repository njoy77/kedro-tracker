import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Lock Screen (and StandBy / banner) presentation of the live game (design §13.2, mockup 18):
/// up to four lines of standings, then the round (large, with the live dot) over the live knock or
/// last-round line, Rules, and Record Round / Report Hand. Rules flips the standings to the cheat
/// sheet (`LiveRules`) until the next round, without unlocking.
///
/// iOS cuts a Lock Screen Live Activity off at about 160 points and centers what overflows, so the
/// layout is budgeted to fit (4 lines × ~23 + the bottom row ~37 + padding) and Dynamic Type is
/// capped at Large here: past that the round and the buttons would be cut off.
struct LiveGameLockScreenView: View {
    let attributes: LiveGameAttributes
    let state: LiveGameAttributes.ContentState
    let isStale: Bool
    /// Read from the app group by default; previews pass it.
    var showsRules: Bool?

    private var isShowingRules: Bool {
        showsRules ?? state.showsRules(gameID: attributes.gameID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isShowingRules {
                LiveRulesSheet()
            } else {
                VStack(spacing: 1) {
                    ForEach(LiveStandingsLayout.lockScreen(state.rows)) { slot in
                        switch slot {
                        case .row(let row):
                            LiveStandingRowView(row: row, style: .lockScreen)
                        case .gap:
                            LiveGapRow()
                        }
                    }
                }
                .opacity(isStale ? 0.5 : 1)
            }
            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private var roundText: String {
        state.phase == .finished
            ? LiveActivityCopy.final
            : LiveActivityCopy.round(state.roundNumber, of: state.plannedRounds)
    }

    /// The line under the round: stale notice, live knock or last round, else the table word.
    private var statusText: Text {
        if isStale { return Text(state.staleLine()).foregroundStyle(Color.silver) }
        return Text(state.statusLine ?? attributes.tableWord).foregroundStyle(Color.silver)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    if state.phase == .active {
                        // Live (the LIVE tag's red); grey once the content is stale.
                        Circle()
                            .fill(isStale ? Color.silverDim : Color.kedroRed)
                            .frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    Text(roundText)
                        .font(.custom(KedroTextStyle.bebas, size: 21))
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundStyle(.cream)
                        .lineLimit(1)
                }
                statusText
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if state.phase == .active {
                LiveRulesButton(gameID: attributes.gameID, isShowingRules: isShowingRules)
            }
            if let action = state.action {
                LiveActionButton(gameID: attributes.gameID, button: action)
            }
        }
    }
}

/// Card values, power cards and knock scoring in the rows' place.
struct LiveRulesSheet: View {
    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
            ForEach(LiveRules.lines) { line in
                GridRow {
                    Text(line.label)
                        .kedroFont(.label)
                        .foregroundStyle(.kedroRed)
                    Text(line.text)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.cream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LiveRules.accessibilityLabel)
    }
}

/// Rules (or Scores, while the rules show) as an App Intent button: flips the Lock Screen in
/// place, no unlock.
struct LiveRulesButton: View {
    let gameID: String
    let isShowingRules: Bool

    var body: some View {
        Button(intent: ShowRulesIntent(gameID: gameID, isOpen: !isShowingRules)) {
            Text(isShowingRules ? LiveActivityCopy.scores : LiveActivityCopy.rules)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.cream)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.14), in: .capsule)
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.18)) }
        }
        .buttonStyle(.plain)
        .accessibilityHint(isShowingRules ? "Shows the standings" : "Shows card values, powers and knock scoring")
    }
}

/// One standings row in the Live Activity.
struct LiveStandingRowView: View {
    enum Style {
        case lockScreen
        case island
    }

    let row: LiveStandingRow
    var style: Style = .lockScreen

    private var nameSize: CGFloat { style == .lockScreen ? 17 : 16 }
    private var scoreSize: CGFloat { style == .lockScreen ? 20 : 18 }

    var body: some View {
        HStack(spacing: 8) {
            Text(row.rankLabel)
                .font(.custom(KedroTextStyle.bebas, size: nameSize))
                .foregroundStyle(row.isLeader ? Color.gold : Color.cream)
                .frame(minWidth: 18, alignment: .leading)
            LiveAvatarView(avatar: row.avatar, size: 18)
                .overlay(alignment: .bottomTrailing) {
                    if row.isDealer {
                        DealerChip(size: 10).offset(x: 3, y: 3)
                    }
                }
            Text(row.name.uppercased())
                .font(.custom(KedroTextStyle.bebas, size: nameSize))
                .foregroundStyle(.cream)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.score)
                .font(.custom(KedroTextStyle.bebas, size: scoreSize))
                .monospacedDigit()
                .foregroundStyle(row.isLeader ? Color.gold : Color.cream)
            LiveDeltaText(delta: row.delta, outcome: row.outcome)
                .frame(width: style == .lockScreen ? 52 : 46, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, style == .lockScreen ? 0 : 1)
        .background {
            if row.isMe {
                RoundedRectangle(cornerRadius: 8).fill(Color.kedroRed.opacity(0.22))
            }
        }
        .overlay(alignment: .leading) {
            if row.isMe {
                Capsule().fill(Color.kedroRed).frame(width: 3).padding(.vertical, 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// The `···` line before your own row.
struct LiveGapRow: View {
    var body: some View {
        Text("···")
            .font(.custom(KedroTextStyle.bebas, size: 16))
            .foregroundStyle(.silverDim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
            .accessibilityHidden(true)
    }
}

/// Record Round / Report Hand as an App Intent button.
struct LiveActionButton: View {
    let gameID: String
    let button: LiveActivityButton

    var body: some View {
        Group {
            switch button.kind {
            case .recordRound:
                Button(intent: RecordRoundIntent(gameID: gameID)) { label }
            case .reportHand:
                Button(intent: ReportHandIntent(gameID: gameID)) { label }
            case .openTable:
                Link(destination: KedroLink.table(gameID: UUID(uuidString: gameID) ?? UUID(), action: .openTable).url) { label }
            }
        }
        .buttonStyle(.plain)
    }

    private var label: some View {
        Text(button.title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.kedroRed, in: .capsule)
    }
}

#Preview("Lock Screen", as: .content, using: WidgetSamples.attributes) {
    LiveGameActivityWidget()
} contentStates: {
    WidgetSamples.afterRound5
    WidgetSamples.rules
    WidgetSamples.liveKnock
    WidgetSamples.truncated
    WidgetSamples.selfReport
}
