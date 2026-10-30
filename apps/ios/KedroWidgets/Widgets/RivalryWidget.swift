import SwiftUI
import WidgetKit

/// Rivalry: "You vs Ana · 5–12" plus the rivalry line (design §13.3, R-06).
struct RivalryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: KedroWidgetKind.rivalry, provider: SnapshotProvider()) { entry in
            RivalryWidgetView(entry: entry)
                .containerBackground(Color.surface, for: .widget)
                .widgetURL(KedroLink.widget(kind: KedroWidgetKind.rivalry).url)
        }
        .configurationDisplayName(WidgetCopy.rivalry)
        .description("You against the person you play most.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

struct RivalryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let rivalry = entry.snapshot.rivalry {
            switch family {
            case .accessoryRectangular: rectangular(rivalry)
            default: medium(rivalry)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: WidgetCopy.rivalry)
                Text(WidgetCopy.noRival)
                    .font(.callout.italic())
                    .foregroundStyle(.silver)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// "5–12", with whoever leads in gold.
    private func record(_ rivalry: RivalrySnapshot, size: CGFloat) -> Text {
        let mine = Text("\(rivalry.myWins)").foregroundStyle(rivalry.myWins > rivalry.theirWins ? Color.gold : Color.cream)
        let theirs = Text("\(rivalry.theirWins)").foregroundStyle(rivalry.theirWins > rivalry.myWins ? Color.gold : Color.cream)
        let dash = Text("–").foregroundStyle(Color.silverDim)
        return Text("\(mine)\(dash)\(theirs)").font(.custom(KedroTextStyle.bebas, size: size))
    }

    private func medium(_ rivalry: RivalrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: WidgetCopy.rivalry)
            HStack(spacing: 14) {
                LiveAvatarView(avatar: rivalry.myAvatar, size: 44)
                record(rivalry, size: 44)
                    .monospacedDigit()
                LiveAvatarView(avatar: rivalry.rivalAvatar, size: 44)
                    .overlay {
                        if rivalry.theirWins > rivalry.myWins {
                            Circle().strokeBorder(Color.gold, lineWidth: 2)
                        }
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(WidgetCopy.you) vs \(rivalry.rivalName)")
                        .kedroFont(.headline)
                        .foregroundStyle(.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Text(rivalry.line)
                .font(.callout.italic())
                .foregroundStyle(.silver)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(WidgetCopy.you) \(rivalry.myWins), \(rivalry.rivalName) \(rivalry.theirWins). \(rivalry.line)")
    }

    private func rectangular(_ rivalry: RivalrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(WidgetCopy.you) vs \(rivalry.rivalName)")
                .kedroFont(.label)
                .widgetAccentable()
            Text("\(rivalry.myWins)–\(rivalry.theirWins)")
                .font(.custom(KedroTextStyle.bebas, size: 26))
            Text(rivalry.line)
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Rivalry", as: .systemMedium) {
    RivalryWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: WidgetSamples.snapshot)
    SnapshotEntry(date: .now, snapshot: WidgetSamples.newPlayer)
}

#Preview("Rivalry, Lock Screen", as: .accessoryRectangular) {
    RivalryWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: WidgetSamples.snapshot)
}
