import SwiftUI

/// Score a Round (design §13.1): practice rounds with synthetic players and cards face up,
/// covering landed, tied and failed. Add up each hand, call the knock, see the round scores.
/// Nothing is logged. At the end, the same rounds can go through the real Round sheet in
/// practice mode.
struct ScoreRoundDrill: View {
    var scenarios: [KnockScenario] = KnockScenario.drill

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var step: Step = .hands
    @State private var typed: [String: Int] = [:]
    @State private var checked = false
    @State private var picked: Int?
    @State private var practice: PracticeTable?

    enum Step { case hands, knock, scores }

    private var scenario: KnockScenario? { scenarios.indices.contains(index) ? scenarios[index] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let scenario {
                    Text("Round \(index + 1) of \(scenarios.count)").kedroFont(.label).foregroundStyle(.silver)
                    switch step {
                    case .hands: handsStep(scenario)
                    case .knock: knockStep(scenario)
                    case .scores: scoresStep(scenario)
                    }
                } else {
                    finished
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { PracticeWatermark() }
        .background(.night)
        .navigationTitle("Score a Round")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $practice) { table in
            PracticeRoundSheet(table: table)
        }
    }

    // MARK: Steps

    @ViewBuilder
    private func handsStep(_ scenario: KnockScenario) -> some View {
        Text("Add Up Each Hand").kedroFont(.display).foregroundStyle(.cream).accessibilityAddTraits(.isHeader)
        Text("Cards are face up. Type each player's total.").foregroundStyle(.silver)
        ForEach(Array(scenario.players.enumerated()), id: \.offset) { offset, player in
            VStack(alignment: .leading, spacing: 8) {
                HandView(name: player.name, cards: player.cards, isKnocker: offset == scenario.knockerIndex, showsTotal: false)
                HStack {
                    TextField("Hand", value: handBinding(player.name), format: .number)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.title3.monospacedDigit())
                        .padding(.horizontal, 12)
                        .frame(width: 96, height: 44)
                        .background(.surface, in: .rect(cornerRadius: 10))
                        .accessibilityLabel("\(player.name)'s hand")
                    if checked {
                        if typed[player.name] == player.hand {
                            Label("Right", systemImage: "checkmark").foregroundStyle(.cream)
                        } else {
                            Label("It's \(ScoreFormat.string(player.hand))", systemImage: "xmark").foregroundStyle(.kedroRed)
                        }
                    }
                }
                .font(.subheadline)
            }
            .padding(12)
            .background(.surfaceRaised, in: .rect(cornerRadius: 16))
        }
        Text("Red Kings are −1, black Kings 13, Jokers 0.").font(.footnote).foregroundStyle(.silverDim)
        Button(checked ? "Call the Knock" : "Check") {
            if checked { step = .knock } else { checked = true }
        }
        .buttonStyle(.kedroPrimary)
        .disabled(!checked && scenario.players.contains { typed[$0.name] == nil })
    }

    @ViewBuilder
    private func knockStep(_ scenario: KnockScenario) -> some View {
        Text("\(scenario.knocker.name) Knocked on \(ScoreFormat.string(scenario.knocker.hand))")
            .kedroFont(.display)
            .foregroundStyle(.cream)
            .accessibilityAddTraits(.isHeader)
        VStack(spacing: 8) {
            ForEach(scenario.players) { player in
                HStack {
                    Text(player.name).foregroundStyle(.cream)
                    Spacer()
                    Text(ScoreFormat.string(player.hand)).kedroFont(.scoreCompact).foregroundStyle(.cream)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .background(.surfaceRaised, in: .rect(cornerRadius: 16))
        Text("What does \(scenario.knocker.name) score?").font(.headline).foregroundStyle(.cream)
        HStack(spacing: 10) {
            ForEach(scenario.choices, id: \.self) { choice in
                Button {
                    picked = choice
                    step = .scores
                } label: {
                    Text(ScoreFormat.string(choice))
                        .kedroFont(.score)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .foregroundStyle(.cream)
                        .background(.surface, in: .rect(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.rule) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ScoreFormat.spoken(choice))
            }
        }
    }

    @ViewBuilder
    private func scoresStep(_ scenario: KnockScenario) -> some View {
        let right = picked == scenario.knockerScore
        HStack(spacing: 10) {
            if let outcome = scenario.outcome { OutcomeBadge(outcome: outcome) }
            Text(right ? "Right." : "Not quite.").font(.headline).foregroundStyle(.cream)
        }
        Text(scenario.verdict).kedroFont(.display).foregroundStyle(.cream)
        Text(scenario.explanation).font(.callout).foregroundStyle(.cream)
        VStack(spacing: 8) {
            ForEach(scenario.players) { player in
                HStack {
                    Text(player.name).foregroundStyle(.cream)
                    if player.name == scenario.knocker.name, let outcome = scenario.outcome {
                        Text(Literal.knockerDelta(outcome, hand: player.hand)).font(.caption).foregroundStyle(.silver)
                    }
                    Spacer()
                    ScoreText(value: scenario.scores[player.name] ?? player.hand, style: .scoreCompact)
                        .foregroundStyle(.cream)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .background(.surfaceRaised, in: .rect(cornerRadius: 16))
        .sensoryFeedback(right ? .success : .error, trigger: index)
        Button(index + 1 == scenarios.count ? "Finish" : "Next Round") { next() }
            .buttonStyle(.kedroPrimary)
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("That's Every Knock").kedroFont(.display).foregroundStyle(.cream)
            Text("Landed, tied and failed. Kedro does this math for you at every real table.")
                .foregroundStyle(.cream)
            Button("Try the Real Round Sheet") {
                Task { practice = try? await PracticeTable.make(from: scenarios.first ?? .landed) }
            }
            .buttonStyle(.kedroGlassWide)
            Text("Same rounds, the real number pad. Nothing is saved.")
                .font(.footnote)
                .foregroundStyle(.silverDim)
            Button(Literal.text("button.done")) { dismiss() }
                .buttonStyle(.kedroPrimary)
        }
    }

    // MARK: Helpers

    private func handBinding(_ name: String) -> Binding<Int?> {
        Binding { typed[name] } set: { typed[name] = $0; checked = false }
    }

    private func next() {
        index += 1
        step = .hands
        typed = [:]
        checked = false
        picked = nil
    }
}

/// A faint PRACTICE watermark: nothing on this screen is logged.
struct PracticeWatermark: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !reduceTransparency {
            Text("PRACTICE")
                .font(.system(size: 96, weight: .black, design: .rounded))
                .foregroundStyle(.cream.opacity(0.04))
                .rotationEffect(.degrees(-28))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A throwaway table for the real Round sheet in practice mode: synthetic guests, an in-memory
/// store and no transport, so nothing reaches this phone's history or any other phone.
struct PracticeTable: Identifiable {
    let session: GameSession
    var id: GameID { session.gameID }

    static func make(from scenario: KnockScenario) async throws -> PracticeTable {
        let device = DeviceID()
        let seats = scenario.players.enumerated().map { index, player in
            Seat(player: .guest(GuestID()), displayName: player.name, order: index, gamesPlayed: 0)
        }
        guard let host = seats.first else { throw GameSession.SessionError.invalidRound }
        let identity = LocalIdentity(deviceID: device, player: host.player, displayName: host.displayName)
        let session = try await GameSession.create(
            config: GameConfig(plannedRounds: 3, scoringMode: .scorekeeper, tableWord: "Practice"),
            host: host,
            others: Array(seats.dropFirst()),
            store: InMemoryGameStore(),
            transport: LocalOnlyTransport(),
            identity: identity,
            clock: HybridLogicalClock(device: device)
        )
        try await session.start()
        return PracticeTable(session: session)
    }
}

/// The table agent's Round sheet over a practice table, under the PRACTICE watermark.
private struct PracticeRoundSheet: View {
    let table: PracticeTable

    var body: some View {
        RoundSheet(session: table.session)
            .overlay { PracticeWatermark() }
    }
}

#Preview {
    NavigationStack { ScoreRoundDrill() }
        .previewEnvironment()
        .preferredColorScheme(.dark)
}
