import ActivityKit
import SwiftUI
import WidgetKit

/// The live game's Live Activity: Lock Screen plus the Dynamic Island (design §13.2).
struct LiveGameActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveGameAttributes.self) { context in
            LiveGameLockScreenView(attributes: context.attributes, state: context.state.resolved(for: context.attributes.mySeatID), isStale: context.isStale)
                .activityBackgroundTint(Color.night.opacity(0.82))
                .activitySystemActionForegroundColor(.cream)
                .widgetURL(tableURL(context.attributes))
        } dynamicIsland: { context in
            let state = context.state.resolved(for: context.attributes.mySeatID)
            let focus = state.myRow ?? state.rows.first
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        KMark(height: 22)
                        Text(state.compactRound)
                            .font(.custom(KedroTextStyle.bebas, size: 22))
                            .foregroundStyle(.cream)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let focus {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(focus.score)
                                .font(.custom(KedroTextStyle.bebas, size: 28))
                                .monospacedDigit()
                                .foregroundStyle(focus.isLeader ? Color.gold : Color.cream)
                            LiveDeltaText(delta: focus.delta, outcome: focus.outcome)
                        }
                        .padding(.trailing, 4)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(focus.accessibilityLabel)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.metadataLine)
                        .kedroFont(.label)
                        .foregroundStyle(.silver)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ForEach(LiveStandingsLayout.expanded(state.rows)) { slot in
                            switch slot {
                            case .row(let row): LiveStandingRowView(row: row, style: .island)
                            case .gap: LiveGapRow()
                            }
                        }
                        .opacity(context.isStale ? 0.5 : 1)
                        HStack(spacing: 8) {
                            Text(context.isStale ? state.staleLine() : (state.statusLine ?? ""))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(context.isStale ? Color.silver : Color.cream)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let action = state.action {
                                LiveActionButton(gameID: context.attributes.gameID, button: action)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    KMark(height: 18)
                    Text(state.compactRound)
                        .font(.custom(KedroTextStyle.bebas, size: 17))
                        .foregroundStyle(.cream)
                }
            } compactTrailing: {
                if let focus {
                    Text("\(Text(focus.ordinal.uppercased() + " · ").foregroundStyle(Color.cream))\(Text(focus.score).foregroundStyle(focus.isLeader ? Color.gold : Color.cream))")
                        .font(.custom(KedroTextStyle.bebas, size: 17))
                        .monospacedDigit()
                        .accessibilityLabel(focus.accessibilityLabel)
                }
            } minimal: {
                Text((focus?.ordinal ?? "").uppercased())
                    .font(.custom(KedroTextStyle.bebas, size: 15))
                    .foregroundStyle(focus?.isLeader == true ? Color.gold : Color.cream)
                    .minimumScaleFactor(0.6)
            }
            .widgetURL(tableURL(context.attributes))
            .keylineTint(.kedroRed)
        }
    }

    private func tableURL(_ attributes: LiveGameAttributes) -> URL? {
        UUID(uuidString: attributes.gameID).map { KedroLink.table(gameID: $0, action: .openTable).url }
    }
}

#Preview("Island compact", as: .dynamicIsland(.compact), using: WidgetSamples.attributes) {
    LiveGameActivityWidget()
} contentStates: {
    WidgetSamples.afterRound5
}

#Preview("Island expanded", as: .dynamicIsland(.expanded), using: WidgetSamples.attributes) {
    LiveGameActivityWidget()
} contentStates: {
    WidgetSamples.liveKnock
    WidgetSamples.truncated
}

#Preview("Island minimal", as: .dynamicIsland(.minimal), using: WidgetSamples.attributes) {
    LiveGameActivityWidget()
} contentStates: {
    WidgetSamples.afterRound5
}
