import SwiftUI

/// Small building blocks shared by the stats screens (profile, head-to-head, board, badges).

/// A number over a caption on a solid card ("25 / Games"), with an optional ⓘ definition.
struct StatTile: View {
    let value: String
    let caption: String
    var info: StatDefinition?

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .kedroFont(.scoreCompact)
                .foregroundStyle(.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 3) {
                Text(caption)
                if let info { InfoButton(definition: info) }
            }
            .font(.caption2)
            .foregroundStyle(.silverDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(.surface, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// A row label with its value and an optional ⓘ (design §12.2: every stat has its definition).
struct StatRow<Value: View>: View {
    let label: String
    var info: StatDefinition?
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.cream)
            if let info { InfoButton(definition: info) }
            Spacer(minLength: 8)
            value
                .foregroundStyle(.cream)
                .monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

extension StatRow where Value == Text {
    init(_ label: String, value: String, info: StatDefinition? = nil) {
        self.label = label
        self.info = info
        self.value = Text(value).fontWeight(.semibold)
    }
}

/// ⓘ: shows the PRD definition of a stat in a popover.
struct InfoButton: View {
    let definition: StatDefinition
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.silverDim)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(definition.name)")
        .popover(isPresented: $isShowing) {
            VStack(alignment: .leading, spacing: 6) {
                Text(definition.name).font(.headline)
                Text(definition.text).font(.callout)
            }
            .padding()
            .frame(idealWidth: 280)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// The PRD §5.1 definitions behind every ⓘ (literal, identical in every level).
nonisolated struct StatDefinition: Hashable, Sendable {
    let name: String
    let text: String

    static let gamesPlayed = StatDefinition(name: "Games played", text: "Finished games, including ended-early ones. Abandoned games never count.")
    static let wins = StatDefinition(name: "Wins", text: "Games won, including shared wins.")
    static let winRate = StatDefinition(name: "Win rate", text: "Wins ÷ games played.")
    static let bestGame = StatDefinition(name: "Best game", text: "Lowest final score in a game.")
    static let worstGame = StatDefinition(name: "Worst game", text: "Highest final score in a game.")
    static let averageGame = StatDefinition(name: "Average per game", text: "Sum of final scores ÷ games played.")
    static let averageRound = StatDefinition(name: "Average per round", text: "Sum of round scores ÷ rounds played.")
    static let currentStreak = StatDefinition(name: "Current win streak", text: "Consecutive most-recent games won.")
    static let longestStreak = StatDefinition(name: "Longest win streak", text: "Longest run of consecutive wins.")
    static let knockRate = StatDefinition(name: "Knock rate", text: "Rounds knocked ÷ rounds played.")
    static let knockSuccess = StatDefinition(name: "Knock success", text: "Knocks with the strictly lowest hand (−10) ÷ total knocks.")
    static let inherentKnocks = StatDefinition(name: "Inherent knocks", text: "Rounds you went out by playing all four cards. −10 if your 0 was lowest alone, never +10. Not counted as knocks.")
    static let knockOutcomes = StatDefinition(name: "Knock outcomes", text: "Landed: strictly lowest hand, −10. Tied: tied for lowest, scores the hand. Failed: someone was lower, hand + 10.")
    static let nemesis = StatDefinition(name: "Nemesis", text: "The player who has finished ahead of you most often in shared games. Ties go to whoever got there first.")
    static let rating = StatDefinition(name: "Rating", text: "Pairwise Elo from finishing order. Starts at 1,000, moves twice as fast for your first 10 games, and shows from your 10th game.")
    static let form = StatDefinition(name: "Form", text: "Your last five finishes, oldest first.")
    static let gamesTogether = StatDefinition(name: "Games together", text: "Finished games you both played.")
    static let finishedAhead = StatDefinition(name: "Finished ahead", text: "Shared games where one of you had the lower final score. Equal scores count for neither.")
}

/// The Bebas section header used across the stats screens.
struct StatsSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title).kedroFont(.label).foregroundStyle(.silver)
            Spacer()
            if let trailing {
                Text(trailing).kedroFont(.label).foregroundStyle(.silverDim)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A person's avatar from stats identity.
struct StatsAvatar: View {
    let identity: StatsParticipant?
    var ref: PlayerRef?
    var size: AvatarView.Size = .compact
    var isLeader = false
    var ring: AvatarView.Ring = .none

    var body: some View {
        AvatarView(
            avatar: identity?.avatar, name: identity?.name ?? "Someone",
            isGuest: (identity?.ref ?? ref)?.isGuest ?? false, size: size, isLeader: isLeader, ring: ring
        )
    }
}

/// The ✓ = ✗ knock record as outcome badges with counts (never color alone).
struct KnockTallyView: View {
    let tally: KnockTally

    var body: some View {
        HStack(spacing: 6) {
            tallyBadge(.landed, tally.landed)
            tallyBadge(.tied, tally.tied)
            tallyBadge(.failed, tally.failed)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tally.accessibilityLabel)
    }

    private func tallyBadge(_ outcome: KnockOutcome, _ count: Int) -> some View {
        HStack(spacing: 3) {
            OutcomeBadge(outcome: outcome, showsWord: false)
            Text("\(count)").font(.footnote.weight(.semibold)).monospacedDigit()
        }
    }
}

/// A title in the viewer's level (TI-xx), in `label` red (design §12.2).
struct TitleLabel: View {
    let title: TitleID
    var voice: Voice

    var body: some View {
        Text(voice.line(title.copyID))
            .kedroFont(.label)
            .foregroundStyle(.kedroRed)
    }
}

extension StatsSnapshot {
    /// A person's stats identity, or one made from what the caller knows.
    func participant(_ ref: PlayerRef, fallbackName: String = "Someone") -> StatsParticipant {
        identity(of: ref) ?? StatsParticipant(ref: ref, seatedAs: ref, name: fallbackName)
    }
}

#Preview("Stats UI") {
    VStack(spacing: 16) {
        HStack {
            StatTile(value: "25", caption: "Games", info: .gamesPlayed)
            StatTile(value: "44%", caption: "Win rate")
        }
        StatRow("Success rate", value: "58%", info: .knockSuccess)
        KnockTallyView(tally: KnockTally(landed: 26, tied: 7, failed: 12))
        StatsSectionHeader(title: "Knocking", trailing: "45")
        TitleLabel(title: .closer, voice: Voice(level: .unhinged))
    }
    .padding()
    .background(.night)
    .previewEnvironment()
}
