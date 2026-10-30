import SwiftUI

/// Game end's progression cards (design §10 items 4–5) for the Table agent's `GameEndView`:
/// ratings with the debut card, badges earned, and the Hall of Shame induction card.
///
/// ```swift
/// @State private var progression: GameEndProgression?
/// …
/// if let progression { GameEndProgressionCards(progression: progression, voice: houseVoice) }
/// .task(id: session.state.status) {
///     progression = await GameEndProgression.load(for: session.gameID, store: app.store, viewer: app.profile?.identity)
/// }
/// ```
struct GameEndProgressionCards: View {
    let progression: GameEndProgression
    /// The house voice for the table.
    let voice: Voice
    /// Names by person, from the game's seats.
    var names: [PlayerRef: String] = [:]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(progression.debuts, id: \.player) { debut in
                card {
                    HStack(spacing: 12) {
                        KMark(height: 30, style: .tinted(.gold))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Debut").kedroFont(.label).foregroundStyle(.gold)
                            Text(progression.debutLine(debut, voice: voice))
                                .font(.subheadline)
                                .foregroundStyle(.cream)
                        }
                    }
                }
            }
            if progression.ratingChanges.contains(where: \.isRated) {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ratings").kedroFont(.label).foregroundStyle(.silver)
                        ForEach(progression.ratingChanges.filter(\.isRated), id: \.player) { change in
                            HStack {
                                Text(names[change.player] ?? "Someone").font(.subheadline).foregroundStyle(.cream)
                                Spacer()
                                Text(change.displayAfter.formatted()).kedroFont(.headline).foregroundStyle(.cream)
                                Text(change.isDebut ? "new" : ScoreFormat.signed(change.delta))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(change.isDebut ? .kedroRed : .silver)
                                    .frame(minWidth: 40, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            if !progression.badgesEarned.isEmpty {
                card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Badges earned").kedroFont(.label).foregroundStyle(.silver)
                        ForEach(progression.badgesEarned, id: \.player) { earned in
                            ForEach(earned.badges) { award in
                                HStack(spacing: 12) {
                                    BadgeCoin(badge: award.badge, isEarned: true, size: 40, showsCategory: false)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(Text(earned.name).fontWeight(.semibold)) · \(award.definition.name)")
                                            .font(.subheadline)
                                            .foregroundStyle(.cream)
                                        Text(voice.line(award.badge.copyID))
                                            .kedroFont(.roast)
                                            .foregroundStyle(.silver)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
            ForEach(progression.shameInductions) { entry in
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hall of Shame").kedroFont(.label).foregroundStyle(.kedroRed)
                        Text(progression.inductionLine(entry, voice: voice))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.cream)
                        ShameEntryRow(entry: entry, voice: voice)
                    }
                }
            }
            if let next = progression.nextGoalLine {
                Text(next).font(.footnote).foregroundStyle(.silver)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surface, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    ScrollView {
        if let progression = StatsSnapshot.preview.gameEnd(for: PreviewData.sampleGameID, viewer: PreviewData.noah.ref) {
            GameEndProgressionCards(
                progression: progression, voice: Voice(level: .spicy),
                names: Dictionary(uniqueKeysWithValues: PreviewData.sampleSeats.map { ($0.player, $0.displayName) })
            )
            .padding()
        }
    }
    .background(.night)
}
