import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Lock Screen (and StandBy / banner) presentation of the live game (design §13.2, mockup 18):
/// the K mark and table word, "ROUND 6 OF 8 · NOAH DEALS", up to five rows, the live knock or
/// last-round line, and Record Round / Report Hand.
struct LiveGameLockScreenView: View {
    let attributes: LiveGameAttributes
    let state: LiveGameAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            VStack(spacing: 2) {
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
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var header: some View {
        HStack(spacing: 6) {
            KMark(height: 16)
            Text("\(attributes.tableWord.uppercased()) · \(state.metadataLine)")
                .kedroFont(.label)
                .foregroundStyle(.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if state.phase == .active {
                Text(LiveActivityCopy.live)
                    .kedroFont(.label)
                    .foregroundStyle(isStale ? Color.silverDim : Color.kedroRed)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Group {
                if isStale {
                    Text(state.staleLine()).foregroundStyle(.silver)
                } else if let line = state.statusLine {
                    Text(line).foregroundStyle(.cream)
                }
            }
            .font(.footnote.weight(.semibold))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let action = state.action {
                LiveActionButton(gameID: attributes.gameID, button: action)
            }
        }
        .padding(.top, 2)
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

    private var nameSize: CGFloat { style == .lockScreen ? 18 : 16 }
    private var scoreSize: CGFloat { style == .lockScreen ? 22 : 18 }

    var body: some View {
        HStack(spacing: 8) {
            Text(row.rankLabel)
                .font(.custom(KedroTextStyle.bebas, size: nameSize))
                .foregroundStyle(row.isLeader ? Color.gold : Color.cream)
                .frame(minWidth: 18, alignment: .leading)
            LiveAvatarView(avatar: row.avatar, size: 20)
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
        .padding(.vertical, 1)
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
    WidgetSamples.liveKnock
    WidgetSamples.truncated
    WidgetSamples.selfReport
}
