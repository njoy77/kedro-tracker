import SwiftUI

/// Pick the title under your name, or No title (design §12.7). Lists earned titles (permanent)
/// and held titles you hold right now; titles render in your level.
struct TitlePickerSheet: View {
    let player: PlayerRef

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var stats: StatsModel { .shared(for: app.store) }
    private var voice: Voice { app.voice }

    var body: some View {
        let snapshot = stats.snapshot
        let chosen = app.profile?.titleID
        let current = snapshot.displayTitle(for: player, chosen: chosen)
        let earned = snapshot.earnedTitles(of: player)
        let held = snapshot.heldTitles(of: player)
        NavigationStack {
            List {
                Section {
                    choiceRow(title: nil, isSelected: current == nil)
                }
                Section {
                    ForEach(earned) { title in
                        choiceRow(title: title, isSelected: current == title)
                    }
                } header: {
                    Text("Earned")
                } footer: {
                    Text("Earned titles are yours for good.")
                }
                Section {
                    if held.isEmpty {
                        Text("You don't hold any right now. Held titles go to the best among your people, with at least 5 ranked people and a real sample.")
                            .font(.footnote)
                            .foregroundStyle(.silver)
                    }
                    ForEach(held) { title in
                        choiceRow(title: title, isSelected: current == title)
                    }
                } header: {
                    Text("Held")
                } footer: {
                    Text("Held titles are recalculated after every game and can be lost. Lose the one you're showing and you switch to your best earned title.")
                }
                Section("Still out there") {
                    ForEach(TitleID.allCases.filter { !earned.contains($0) && !held.contains($0) }) { title in
                        lockedRow(title)
                    }
                }
            }
            .navigationTitle("Your Title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Literal.text("button.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func choiceRow(title: TitleID?, isSelected: Bool) -> some View {
        Button {
            choose(title)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(voice.line(title.copyID)).font(.body.weight(.semibold)).foregroundStyle(.cream)
                        Text(voice.line(title.taglineID)).font(.caption).foregroundStyle(.silver)
                    } else {
                        Text("No title").font(.body.weight(.semibold)).foregroundStyle(.cream)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.kedroRed).fontWeight(.semibold)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func lockedRow(_ title: TitleID) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(voice.line(title.copyID)).font(.body).foregroundStyle(.silverDim)
            Text(TitleRules.howToGet(title)).font(.caption).foregroundStyle(.silverDim)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(voice.line(title.copyID)), locked. \(TitleRules.howToGet(title))")
    }

    private func choose(_ title: TitleID?) {
        guard var profile = app.profile else { return }
        profile.titleID = title?.rawValue
        app.profiles.save(profile)
    }
}

extension TitleRules {
    /// How to get a title (design §12.7), literal.
    static func howToGet(_ title: TitleID) -> String {
        switch title.kind {
        case .earned(let badge?):
            "Badge: \(badge.definition.name) (\(badge.definition.isSecret ? "secret" : badge.definition.rule))."
        case .earned(nil):
            "Everyone starts here."
        case .held(let metric):
            metric.howToHold
        }
    }
}

extension HeldMetric {
    /// The literal rule for holding a title.
    var howToHold: String {
        switch self {
        case .knockSuccess: "Best knock success among your people (15+ knocks)."
        case .knockRate: "Highest knock rate among your people (50+ rounds)."
        case .knocksBeaten: "Most times beating someone else's knock (10+ games)."
        case .averageRound: "Lowest average round among your people (20+ games)."
        case .redKingsThisYear: "Most red Kings in final hands this year (10+ games this year)."
        case .rating: "#1 by rating among your people."
        case .bottledThisYear: "Most final-round leads blown this year (10+ games this year)."
        }
    }
}

#Preview {
    Text("Profile")
        .sheet(isPresented: .constant(true)) {
            TitlePickerSheet(player: PreviewData.noah.ref)
        }
        .previewEnvironment()
}
