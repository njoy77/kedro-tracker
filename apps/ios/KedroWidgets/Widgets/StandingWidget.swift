import SwiftUI
import WidgetKit

/// Standing: rank, rating and weekly movement; the 5-step meter before game 5 (design §13.3).
struct StandingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: KedroWidgetKind.standing, provider: SnapshotProvider()) { entry in
            StandingWidgetView(entry: entry)
                .containerBackground(Color.surface, for: .widget)
                .widgetURL(KedroLink.widget(kind: KedroWidgetKind.standing).url)
        }
        .configurationDisplayName(WidgetCopy.standing)
        .description(WidgetCopy.standingDescription)
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct StandingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var standing: StandingSnapshot {
        entry.snapshot.standing
            ?? StandingSnapshot(rank: nil, scopeLabel: WidgetCopy.global, rating: nil, weeklyMovement: 0, gamesPlayed: 0)
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    // MARK: Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: WidgetCopy.standing)
            Spacer(minLength: 4)
            if let rank = standing.rank, let rating = standing.rating {
                Text("#\(rank)")
                    .font(.custom(KedroTextStyle.bebas, size: 56))
                    .foregroundStyle(rank == 1 ? Color.gold : Color.cream)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("\(standing.scopeLabel) · \(Text(rating.formatted()).bold().foregroundStyle(Color.cream))")
                    .font(.caption)
                    .foregroundStyle(.silver)
                movement
                    .padding(.top, 4)
            } else {
                Text(WidgetCopy.notRanked)
                    .font(.custom(KedroTextStyle.bebas, size: 26))
                    .foregroundStyle(.cream)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                FiveStepMeter(steps: standing.meterSteps)
                Text(WidgetCopy.meter(standing.meterSteps))
                    .kedroFont(.label)
                    .foregroundStyle(.silver)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var movement: some View {
        let places = standing.weeklyMovement
        HStack(spacing: 3) {
            if places != 0 {
                Image(systemName: places > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 8))
            }
            Text(WidgetCopy.movement(places))
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(places > 0 ? Color.kedroRed : Color.silver)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetCopy.movementAccessibility(places))
    }

    // MARK: Lock Screen

    private var circular: some View {
        Group {
            if let rank = standing.rank {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: -2) {
                        Text("#\(rank)")
                            .font(.custom(KedroTextStyle.bebas, size: 22))
                            .minimumScaleFactor(0.5)
                        if let rating = standing.rating {
                            Text(rating.formatted())
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                }
            } else {
                Gauge(value: Double(standing.meterSteps), in: 0...Double(StandingSnapshot.gamesToRank)) {
                    KMark(height: 10)
                } currentValueLabel: {
                    Text("\(standing.meterSteps)")
                        .font(.custom(KedroTextStyle.bebas, size: 18))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            }
        }
        .widgetAccentable()
        .accessibilityElement(children: .combine)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Kedro · \(WidgetCopy.standing)")
                .kedroFont(.label)
                .widgetAccentable()
            if let rank = standing.rank, let rating = standing.rating {
                Text("#\(rank) · \(rating.formatted())")
                    .font(.custom(KedroTextStyle.bebas, size: 24))
                Text("\(standing.scopeLabel) · \(WidgetCopy.movement(standing.weeklyMovement))")
                    .font(.caption2)
            } else {
                Text(WidgetCopy.notRanked)
                    .font(.headline)
                Gauge(value: Double(standing.meterSteps), in: 0...Double(StandingSnapshot.gamesToRank)) {
                    Text(WidgetCopy.meter(standing.meterSteps))
                }
                .gaugeStyle(.accessoryLinearCapacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Standing", as: .systemSmall) {
    StandingWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: WidgetSamples.snapshot)
    SnapshotEntry(date: .now, snapshot: WidgetSamples.newPlayer)
}

#Preview("Standing, Lock Screen", as: .accessoryRectangular) {
    StandingWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: WidgetSamples.snapshot)
    SnapshotEntry(date: .now, snapshot: WidgetSamples.newPlayer)
}

#Preview("Standing, circular", as: .accessoryCircular) {
    StandingWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: WidgetSamples.snapshot)
    SnapshotEntry(date: .now, snapshot: WidgetSamples.newPlayer)
}
