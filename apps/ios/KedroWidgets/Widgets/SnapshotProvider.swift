import SwiftUI
import WidgetKit

struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
    /// True for the gallery and placeholders (sample data).
    var isSample = false
}

/// Every Kedro widget reads the same app-group snapshot. The timeline never refreshes on its own:
/// the app reloads it when a game finishes and on claims, so widgets stay frozen during live games
/// (design §13.3).
struct SnapshotProvider: TimelineProvider {
    var store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSamples.snapshot, isSample: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview, store.load() == nil {
            completion(placeholder(in: context))
        } else {
            completion(entry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: store.load() ?? .empty)
    }
}

/// Literal widget strings that aren't in the copy deck yet.
/// TODO(copy): move these to `docs/kedro-ios-copy.md` §20 (literal) and the deck.
enum WidgetCopy {
    static let standing = "Standing"
    static let rivalry = "Rivalry"
    static let nextBadge = "Next Badge"
    static let notRanked = "Not ranked yet"
    static let noRival = "Play a few games. Somebody will start to bother you."
    static let noBadge = "Every badge is yours. Go outside."
    static let you = "You"

    static func meter(_ n: Int) -> String { "\(n) of \(StandingSnapshot.gamesToRank)" }

    static func movement(_ places: Int) -> String {
        places == 0 ? "Same as last week" : "\(abs(places)) this week"
    }
}

/// The small header every widget shares: the K mark and a label.
struct WidgetHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            KMark(height: 14)
            Text(title)
                .kedroFont(.label)
                .foregroundStyle(.silver)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The 5-step meter before a player is ranked (design §13.3; `Gauge` per §15).
struct FiveStepMeter: View {
    let steps: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<StandingSnapshot.gamesToRank, id: \.self) { index in
                Capsule()
                    .fill(index < steps ? Color.kedroRed : Color.rule)
                    .frame(height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(WidgetCopy.meter(steps))
    }
}
