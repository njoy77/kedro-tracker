import SwiftUI

/// Bragging Rights: the badge grid with Next up (design §12.6). Public: anyone's badges, in the
/// viewer's level. Secret badges stay hidden until earned.
struct BadgesView: View {
    let player: PlayerRef

    @Environment(AppModel.self) private var app
    @State private var selected: BadgeID?

    private var stats: StatsModel { .shared(for: app.store) }
    private var voice: Voice { app.voice }
    private var isMe: Bool {
        guard let me = app.profile?.identity else { return false }
        return stats.snapshot.options.canonical(me) == stats.snapshot.options.canonical(player)
    }

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 8, alignment: .top)]

    var body: some View {
        let snapshot = stats.snapshot
        let record = snapshot.record(player)
        let earned = record?.badges ?? [:]
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isMe, let record {
                    nextUp(BadgeEvaluator.progress(record))
                }
                ForEach(BadgeCategory.allCases) { category in
                    let badges = BadgeDefinition.all.filter { $0.category == category }
                    VStack(alignment: .leading, spacing: 10) {
                        StatsSectionHeader(title: category.name, trailing: "\(badges.count { earned[$0.id] != nil }) of \(badges.count)")
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(badges, id: \.id) { badge in
                                cell(badge, isEarned: earned[badge.id] != nil)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(.night)
        .navigationTitle("Bragging Rights · \(earned.count) of \(BadgeDefinition.all.count)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { badge in
            BadgeDetailSheet(badge: badge, award: earned[badge], share: snapshot.badgeShare(badge), voice: voice)
        }
        .task { await stats.follow(app.store, viewer: app.profile?.identity) }
    }

    @ViewBuilder
    private func nextUp(_ progress: [BadgeProgress]) -> some View {
        if !progress.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                StatsSectionHeader(title: "Next up")
                VStack(spacing: 12) {
                    ForEach(progress.prefix(3)) { item in
                        Button { selected = item.badge } label: { NextUpRow(progress: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(14)
                .background(.surface, in: .rect(cornerRadius: 16))
            }
        }
    }

    private func cell(_ badge: BadgeDefinition, isEarned: Bool) -> some View {
        Button {
            selected = badge.id
        } label: {
            VStack(spacing: 6) {
                BadgeCoin(badge: badge.id, isEarned: isEarned, size: 64)
                Text(badge.isSecret && !isEarned ? "Secret" : badge.name)
                    .font(.caption2)
                    .foregroundStyle(isEarned ? .cream : .silverDim)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A Next up row: the coin, the rule, and progress.
private struct NextUpRow: View {
    let progress: BadgeProgress

    var body: some View {
        let definition = progress.badge.definition
        HStack(spacing: 12) {
            BadgeCoin(badge: progress.badge, isEarned: false, size: 40, showsCategory: false)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(definition.name).fontWeight(.semibold)) · \(definition.rule)")
                    .font(.subheadline)
                    .foregroundStyle(.cream)
                HStack(spacing: 8) {
                    Text(progress.remaining == 1 ? "\(progress.label) · next one" : progress.label)
                        .font(.caption)
                        .foregroundStyle(.silverDim)
                    ProgressView(value: progress.fraction)
                        .tint(.kedroRed)
                        .frame(maxWidth: 120)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(definition.name), \(definition.rule), \(progress.label)")
    }
}

/// The badge large, its line in your level, the game it was earned in, and how rare it is.
struct BadgeDetailSheet: View {
    let badge: BadgeID
    let award: BadgeAward?
    /// Share of players who have it (0…1).
    let share: Double?
    let voice: Voice

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let definition = badge.definition
        let isHidden = definition.isSecret && award == nil
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    BadgeCoin(badge: badge, isEarned: award != nil, size: 140)
                        .padding(.top, 12)
                    Text(isHidden ? "Secret" : definition.name)
                        .kedroFont(.display)
                        .foregroundStyle(.cream)
                    if !isHidden {
                        Text("\(definition.tier.name) · \(definition.category.name)")
                            .kedroFont(.label)
                            .foregroundStyle(.silver)
                    }
                    if award != nil {
                        Text(voice.line(badge.copyID))
                            .kedroFont(.roast)
                            .foregroundStyle(.cream)
                            .multilineTextAlignment(.center)
                    }
                    Text(isHidden ? "Keep playing. You'll know it when it happens." : "How: \(definition.rule).")
                        .font(.callout)
                        .foregroundStyle(.silver)
                        .multilineTextAlignment(.center)
                    if let caption = earnedCaption {
                        Text(caption).font(.footnote).foregroundStyle(.silverDim).multilineTextAlignment(.center)
                    }
                    if !isHidden, let avatar = definition.unlocksAvatar {
                        Label("Unlocks the curated avatar \(avatar.displayName).", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.footnote)
                            .foregroundStyle(.silver)
                    }
                    if !isHidden, let title = TitleID.unlocked(by: badge) {
                        Text("Unlocks the title \(voice.line(title.copyID)).")
                            .font(.footnote)
                            .foregroundStyle(.silver)
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .background(.night)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Literal.text("button.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// "Cold Deck, R8 · earned by 14% of players"
    private var earnedCaption: String? {
        var parts: [String] = []
        if let award, let word = award.tableWord {
            parts.append(award.roundNumber.map { "\(word), R\($0)" } ?? word)
        } else if let date = award?.date {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let share { parts.append("earned by \(StatsFormat.percent(share)) of players") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension StatsSnapshot {
    /// The share of players on this phone (accounts and claimed guests) who have a badge.
    func badgeShare(_ badge: BadgeID) -> Double? {
        let people = records.values.filter { !$0.isGuest }
        guard !people.isEmpty else { return nil }
        return Double(people.count { $0.badges[badge] != nil }) / Double(people.count)
    }

    /// Curated avatars this person may pick (the secret two need their badges; design §12.6).
    func availableAvatars(for ref: PlayerRef) -> [CuratedAvatarID] {
        AvatarUnlocks.available(earned: Set(record(ref)?.badges.keys.map { $0 } ?? []))
    }
}

#Preview("Your badges") {
    NavigationStack { BadgesView(player: PreviewData.noah.ref) }
        .previewEnvironment()
}

#Preview("Detail") {
    Text("Badges")
        .sheet(isPresented: .constant(true)) {
            BadgeDetailSheet(
                badge: .ghostHand,
                award: BadgeAward(badge: .ghostHand, gameID: PreviewData.sampleGameID, tableWord: "Cold Deck", roundNumber: 8),
                share: 0.14, voice: Voice(level: .spicy)
            )
        }
}
