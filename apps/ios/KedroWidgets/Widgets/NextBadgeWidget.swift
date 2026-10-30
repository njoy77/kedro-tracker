import SwiftUI
import WidgetKit

/// Next Badge: the closest badge and its progress (design §13.3).
struct NextBadgeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: KedroWidgetKind.nextBadge, provider: SnapshotProvider()) { entry in
            NextBadgeWidgetView(entry: entry)
                .containerBackground(Color.surface, for: .widget)
                .widgetURL(KedroLink.widget(kind: KedroWidgetKind.nextBadge).url)
        }
        .configurationDisplayName(WidgetCopy.nextBadge)
        .description(WidgetCopy.nextBadgeDescription)
        .supportedFamilies([.systemSmall])
    }
}

struct NextBadgeWidgetView: View {
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: WidgetCopy.nextBadge)
            if let badge = entry.snapshot.nextBadge {
                BadgeCoin(tier: badge.tier)
                    .frame(width: 54, height: 54)
                    .padding(.vertical, 8)
                Text(badge.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(badge.progressLine)
                    .font(.caption2)
                    .foregroundStyle(.silverDim)
                    .lineLimit(1)
                Gauge(value: badge.fraction) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(.kedroRed)
                    .padding(.top, 4)
            } else {
                Spacer()
                Text(WidgetCopy.noBadge)
                    .font(.callout.italic())
                    .foregroundStyle(.silver)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// A dark coin with the K mark struck in the middle, rimmed by tier (design §12.6).
struct BadgeCoin: View {
    let tier: BadgeTierSnapshot

    private var rim: LinearGradient {
        let colors: [Color] = switch tier {
        case .silver: [Color(white: 0.85), Color(white: 0.45)]
        case .red: [.kedroRed, .kedroRedDeep]
        case .gold: [.gold, Color(red: 0.6, green: 0.45, blue: 0.08)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            Circle().fill(rim)
            Circle().fill(Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x1A / 255)).padding(4)
            KMark(height: 24)
        }
        .accessibilityHidden(true)
    }
}

#Preview("Next Badge", as: .systemSmall) {
    NextBadgeWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: WidgetSamples.snapshot)
    SnapshotEntry(date: .now, snapshot: WidgetSamples.newPlayer)
}
