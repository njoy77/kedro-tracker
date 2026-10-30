import SwiftUI

/// The Knock Calculator (design §13.1): opened from Rules or any **Why?**, prefilled from a round,
/// editable without touching the game. Shows every round score with the knock's math.
struct KnockCalculatorView: View {
    let prefill: Round?

    @Environment(AppModel.self) private var app
    @State private var calculator = KnockCalculator.example
    @State private var loaded = false

    init(prefill: Round?) {
        self.prefill = prefill
    }

    var body: some View {
        Form {
            resultSection

            Section {
                ForEach($calculator.entries) { $entry in
                    HandEntryRow(
                        entry: $entry,
                        isKnocker: calculator.knocker == entry.id,
                        score: calculator.scores[entry.id],
                        outcome: calculator.knocker == entry.id ? calculator.outcome : nil
                    ) {
                        calculator.knocker = entry.id
                    }
                    .swipeActions {
                        if calculator.entries.count > KnockCalculator.playerRange.lowerBound {
                            Button(Literal.text("button.remove"), role: .destructive) { calculator.remove(entry.id) }
                        }
                    }
                }
                if calculator.entries.count < KnockCalculator.playerRange.upperBound {
                    Button("Add a Player", systemImage: "plus") { calculator.addPlayer() }
                }
            } header: {
                Text("Hands")
            } footer: {
                Text("Tap the hand icon to pick who knocked. Hands go from −2 (two red Kings) up.")
            }

            Section {
                Toggle(TableText.text("label.inherentKnock"), isOn: $calculator.inherent)
                    .tint(.kedroRed)
            } footer: {
                Text(TableText.text("label.inherentKnockHint"))
            }

            Section {
                Text("Strictly lowest: −10 flat. Tied for lowest: the hand. Beaten: the hand + 10. Went out with all four cards: −10 if strictly lowest, otherwise 0, never +10. Everyone else scores their hand.")
                    .font(.footnote)
                    .foregroundStyle(.silver)
                NavigationLink(value: AppRoute.rules) { Label("All the Rules", systemImage: "book") }
            }
        }
        .navigationTitle("Knock Calculator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Examples", systemImage: "list.bullet") {
                    ForEach(KnockCalculator.examples, id: \.title) { example in
                        Button(example.title) { calculator = example.calculator }
                    }
                }
            }
            if prefill != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") { load(force: true) }
                }
            }
        }
        .onAppear { load(force: false) }
    }

    @ViewBuilder
    private var resultSection: some View {
        Section {
            if let outcome = calculator.outcome, let verdict = calculator.verdict, let knockLine = calculator.knockLine {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        OutcomeBadge(outcome: outcome)
                        Text(knockLine)
                            .font(.subheadline)
                            .foregroundStyle(.silver)
                    }
                    Text(verdict).kedroFont(.display).foregroundStyle(.cream)
                    if let explanation = calculator.explanation {
                        Text(explanation).font(.callout).foregroundStyle(.cream)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            } else {
                Text("Every hand needs a number, and someone has to knock.")
                    .foregroundStyle(.silver)
            }
        }
    }

    private func load(force: Bool) {
        guard force || !loaded else { return }
        loaded = true
        guard let prefill else { return }
        let state = app.liveGame?.state
        calculator = KnockCalculator(round: prefill, order: state?.seats.map(\.id) ?? []) { seat in
            state?.seat(seat)?.displayName
        }
    }
}

/// One player's hand: name, the knocker toggle, the hand value, and the round score it makes.
private struct HandEntryRow: View {
    @Binding var entry: KnockCalculator.Entry
    var isKnocker: Bool
    var score: Int?
    var outcome: KnockOutcome?
    var makeKnocker: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(isKnocker ? "Knocker" : "Make Knocker", systemImage: isKnocker ? "hand.raised.fill" : "hand.raised") {
                makeKnocker()
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(isKnocker ? Color.kedroRed : .silverDim)
            .buttonStyle(.borderless)
            .frame(width: 44, height: 44)
            .accessibilityAddTraits(isKnocker ? .isSelected : [])

            TextField("Name", text: $entry.name)
                .textInputAutocapitalization(.words)

            TextField("Hand", value: $entry.hand, format: .number)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.title3.monospacedDigit())
                .frame(width: 56)
                .accessibilityLabel("\(entry.name)'s hand")
                .onChange(of: entry.hand) { _, hand in
                    entry.hand = min(max(hand, Round.handRange.lowerBound), Round.handRange.upperBound)
                }

            Stepper("Hand", value: $entry.hand, in: Round.handRange)
                .labelsHidden()

            VStack(alignment: .trailing, spacing: 0) {
                if let score {
                    ScoreText(value: score, style: .scoreCompact).foregroundStyle(.cream)
                }
                if let outcome {
                    Text(Literal.knockerDelta(outcome, hand: entry.hand)).font(.caption2).foregroundStyle(.silver)
                }
            }
            .frame(minWidth: 52, alignment: .trailing)
        }
    }
}

#Preview("Example") {
    NavigationStack { KnockCalculatorView(prefill: nil).appRouteDestinations() }
        .previewEnvironment()
}

#Preview("Went out, beaten") {
    NavigationStack { KnockCalculatorView(prefill: Round(number: 1, hands: [PreviewData.noahSeat: 0, PreviewData.anaSeat: -2, PreviewData.benSeat: 9], knocker: PreviewData.noahSeat, isInherent: true)).appRouteDestinations() }
        .previewEnvironment()
}

#Preview("Prefilled from Round 5") {
    NavigationStack { KnockCalculatorView(prefill: PreviewData.sampleRounds[4]).appRouteDestinations() }
        .previewEnvironment(AppModel.preview(liveGame: true))
}
