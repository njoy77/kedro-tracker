import SwiftUI

/// "Learn Cambio in 2 minutes" (design §13.1): five cards (setup, card values, powers, sticking,
/// knocking and the knock gamble) with real card faces, ending in a knock-gamble quiz.
/// Rule text is literal; only the closing line uses the voice.
struct LearnCardsView: View {
    enum Page: Int, CaseIterable, Identifiable {
        case setup, values, powers, sticking, knocking, quiz
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .setup: "Setup"
            case .values: "Card Values"
            case .powers: "Power Cards"
            case .sticking: "Sticking"
            case .knocking: "The Knock Gamble"
            case .quiz: "Quiz"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page = .setup

    var body: some View {
        TabView(selection: $page) {
            ForEach(Page.allCases) { page in
                ScrollView {
                    content(for: page)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        .background(.night)
        .safeAreaInset(edge: .bottom) {
            if page != .quiz {
                Button(page == .knocking ? "Take the Quiz" : "Next") {
                    withAnimation(reduceMotion ? nil : .smooth) {
                        page = Page(rawValue: page.rawValue + 1) ?? .quiz
                    }
                }
                .buttonStyle(.kedroPrimary)
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(for page: Page) -> some View {
        switch page {
        case .setup: SetupCard()
        case .values: ValuesCard()
        case .powers: PowersCard()
        case .sticking: StickingCard()
        case .knocking: KnockingCard()
        case .quiz: KnockQuiz { dismiss() }
        }
    }
}

// MARK: - Cards

private struct LearnCardText: View {
    let heading: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .kedroFont(.display)
                .foregroundStyle(.cream)
                .accessibilityAddTraits(.isHeader)
            ForEach(lines, id: \.self) { line in
                Text(line).font(.body).foregroundStyle(.cream)
            }
        }
    }
}

/// A face-down card.
private struct CardBack: View {
    var width: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .fill(Color.kedroRedDeep)
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.09)
                    .strokeBorder(.cream.opacity(0.5), lineWidth: 1.5)
                    .padding(width * 0.07)
            }
            .overlay { KMark(height: width * 0.5).opacity(0.6) }
            .frame(width: width, height: width * 1.4)
            .accessibilityHidden(true)
    }
}

private struct SetupCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            LearnCardText(heading: "Four Cards, Face Down", lines: [
                "Everyone gets 4 cards face down in a 2×2 grid. No looking at your own, unless a power card says so.",
                "On your turn, draw a card. Keep it by swapping it for one in your grid, or discard it.",
                "Lowest total after the last round wins the game.",
            ])
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow { CardBack(); CardBack() }
                GridRow { CardBack(); CardBack() }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel("Four cards face down in a two by two grid")
        }
    }
}

private struct ValuesCard: View {
    private let samples: [PlayingCard] = [
        .card(.ace, .spades), .card(.number(7), .hearts), .card(.number(10), .clubs), .card(.jack, .diamonds),
        .card(.queen, .spades), .card(.king, .clubs), .card(.king, .hearts), .joker,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            LearnCardText(heading: "Low Is Good", lines: [
                "Ace is 1, 2 to 10 are face value, Jack 11, Queen 12.",
                "Black Kings are 13: the worst card in the deck. Red Kings are −1: the best. Jokers are 0.",
                "Your hand is the total of whatever's left in your grid when the round ends.",
            ])
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 16) {
                ForEach(samples) { PlayingCardView(card: $0, width: 60, showsValue: true) }
            }
        }
    }
}

private struct PowersCard: View {
    private let powers: [(PlayingCard, String, String)] = [
        (.card(.number(7), .hearts), "7 or 8", "Peek at one of your own cards."),
        (.card(.number(9), .clubs), "9 or 10", "Peek at one of an opponent's cards."),
        (.card(.jack, .spades), "Jack or Queen", "Blind switch: swap one of yours with an opponent's. No looking."),
        (.card(.king, .spades), "Black King", "Look at any card, then swap it if you want."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LearnCardText(heading: "Discard a Power", lines: [
                "Discard one of these straight from the deck and you get its power.",
            ])
            ForEach(powers, id: \.1) { card, name, power in
                HStack(spacing: 16) {
                    PlayingCardView(card: card, width: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name.uppercased()).kedroFont(.headline).foregroundStyle(.cream)
                        Text(power).font(.callout).foregroundStyle(.silver)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct StickingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            LearnCardText(heading: "Stick It", lines: [
                "When anyone discards a card, anyone holding the same rank can slap theirs on top right away. One less card in your grid.",
                "Get it wrong and the table handles it under the physical rules. Whatever you end up holding counts in your hand.",
                "Stick all four and you've gone out: your hand is 0, and you knock automatically when your turn comes.",
            ])
            HStack(spacing: 18) {
                VStack(spacing: 6) {
                    PlayingCardView(card: .card(.number(6), .spades), width: 70)
                    Text("Discarded").font(.caption).foregroundStyle(.silver)
                }
                Image(systemName: "arrow.left").font(.title2).foregroundStyle(.kedroRed).accessibilityHidden(true)
                VStack(spacing: 6) {
                    PlayingCardView(card: .card(.number(6), .hearts), width: 70)
                    Text("Your 6, stuck").font(.caption).foregroundStyle(.silver)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct KnockingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LearnCardText(heading: "Knock, Then Pray", lines: [
                "Think you're lowest? Knock on your turn. Everyone else gets one more turn, then all cards flip.",
                "Every round ends with exactly one knock. Kedro does all the math.",
            ])
            outcomeRow(.landed, "Strictly lowest", "You score −10, whatever your hand.")
            outcomeRow(.tied, "Tied for lowest", "You score your hand.")
            outcomeRow(.failed, "Someone beat you", "You score your hand + 10.")
            Text("Everyone else always scores their own hand.")
                .font(.callout)
                .foregroundStyle(.silver)
            Text("Went Out")
                .kedroFont(.headline)
                .foregroundStyle(.cream)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 4)
            outcomeRow(.landed, "Strictly lowest", "Played all four cards and everyone else is above 0: −10.")
            outcomeRow(.noPenalty, "Tied or beaten", "Someone matched or beat your 0: you score 0. Going out never takes the +10.")
        }
    }

    private func outcomeRow(_ outcome: KnockOutcome, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            OutcomeBadge(outcome: outcome).frame(minWidth: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.cream)
                Text(detail).font(.callout).foregroundStyle(.silver)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Quiz

/// The knock-gamble quiz: a few rounds, cards face up; pick what the knocker scores.
struct KnockQuiz: View {
    var scenarios: [KnockScenario] = KnockScenario.quiz
    var onFinish: () -> Void

    @State private var index = 0
    @State private var picked: Int?
    @State private var correct = 0

    private var isDone: Bool { index >= scenarios.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if isDone {
                Text("\(correct) of \(scenarios.count)")
                    .kedroFont(.scoreLarge)
                    .foregroundStyle(correct == scenarios.count ? Color.gold : .cream)
                Text(correct == scenarios.count
                     ? "You know the knock gamble. Go sit down."
                     : "Close enough. The Knock Calculator is in Rules any time a knock confuses the table.")
                    .font(.body)
                    .foregroundStyle(.cream)
                Button(Literal.text("button.done"), action: onFinish)
                    .buttonStyle(.kedroPrimary)
                    .padding(.top, 8)
                    .onAppear { LearnCompletion.mark(.cards) }
            } else {
                let scenario = scenarios[index]
                Text("Question \(index + 1) of \(scenarios.count)").kedroFont(.label).foregroundStyle(.silver)
                Text("What does \(scenario.knocker.name) score?")
                    .kedroFont(.display)
                    .foregroundStyle(.cream)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 10) {
                    ForEach(Array(scenario.players.enumerated()), id: \.offset) { offset, player in
                        HandView(name: player.name, cards: player.cards, isKnocker: offset == scenario.knockerIndex, wentOut: scenario.inherent)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(scenario.choices, id: \.self) { choice in
                        choiceButton(choice, scenario: scenario)
                    }
                }
                if let picked {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(picked == scenario.knockerScore ? "Right." : "Not quite.")
                            .font(.headline)
                            .foregroundStyle(.cream)
                        Text(scenario.verdict).kedroFont(.headline).foregroundStyle(.cream)
                        Text(scenario.explanation).font(.callout).foregroundStyle(.silver)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.surface, in: .rect(cornerRadius: 14))
                    .accessibilityElement(children: .combine)
                    Button(index + 1 == scenarios.count ? "See How You Did" : "Next Question") {
                        index += 1
                        self.picked = nil
                    }
                    .buttonStyle(.kedroPrimary)
                }
            }
        }
        .sensoryFeedback(trigger: picked) { _, new in
            guard let new, !isDone else { return nil }
            return new == scenarios[index].knockerScore ? .success : .error
        }
    }

    private func choiceButton(_ choice: Int, scenario: KnockScenario) -> some View {
        let isAnswer = choice == scenario.knockerScore
        let isPicked = picked == choice
        return Button {
            guard picked == nil else { return }
            picked = choice
            if isAnswer { correct += 1 }
        } label: {
            VStack(spacing: 2) {
                Text(ScoreFormat.string(choice)).kedroFont(.score)
                if picked != nil, isAnswer {
                    Image(systemName: "checkmark").font(.caption.bold())
                } else if isPicked {
                    Image(systemName: "xmark").font(.caption.bold())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(picked != nil && isAnswer ? Color.night : .cream)
            .background(picked != nil && isAnswer ? Color.cream : .surfaceRaised, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(isPicked && !isAnswer ? Color.kedroRed : .rule, lineWidth: isPicked ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(picked != nil)
        .accessibilityLabel(ScoreFormat.spoken(choice))
        .accessibilityValue(picked == nil ? "" : (isAnswer ? "Correct answer" : (isPicked ? "Your answer, wrong" : "")))
    }
}

#Preview("Learn Cambio") {
    NavigationStack { LearnCardsView() }
        .previewEnvironment()
        .preferredColorScheme(.dark)
}

#Preview("Quiz") {
    ScrollView { KnockQuiz {}.padding() }
        .background(.night)
        .previewEnvironment()
        .preferredColorScheme(.dark)
}
