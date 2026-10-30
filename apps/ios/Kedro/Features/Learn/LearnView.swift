import SwiftUI

/// Learning Cambio (design §13.1): the 2-minute cards ending in the knock-gamble quiz, the Score a
/// Round drill, the Rules reference and the Knock Calculator.
///
/// A route destination (`AppRoute.learn`), so it doesn't create a NavigationStack.
struct LearnView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: -14) {
                        PlayingCardView(card: .card(.king, .hearts), width: 46).rotationEffect(.degrees(-8))
                        PlayingCardView(card: .joker, width: 46)
                        PlayingCardView(card: .card(.ace, .spades), width: 46).rotationEffect(.degrees(8))
                    }
                    .accessibilityHidden(true)
                    Text(app.voice.line("O-04"))
                        .font(.callout)
                        .foregroundStyle(.cream)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                NavigationLink(value: LearnRoute.cards) {
                    row("Learn Cambio in 2 Minutes", "Setup, card values, powers, sticking and the knock. Then a quiz.", systemImage: "rectangle.stack")
                }
                NavigationLink(value: LearnRoute.drill) {
                    row("Score a Round", "Practice rounds with the cards face up: landed, tied, failed and going out.", systemImage: "number.square")
                }
            }

            Section {
                NavigationLink(value: AppRoute.rules) {
                    row("Rules", "Every rule, searchable.", systemImage: "book")
                }
                NavigationLink(value: AppRoute.knockCalculator(nil)) {
                    row("Knock Calculator", "Type in the hands to see how a round scores.", systemImage: "function")
                }
            }
        }
        .navigationTitle("Learn Cambio")
        .navigationDestination(for: LearnRoute.self) { route in
            switch route {
            case .cards: LearnCardsView()
            case .drill: ScoreRoundDrill()
            }
        }
    }

    private func row(_ title: String, _ detail: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.kedroRed)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.cream)
                Text(detail).font(.footnote).foregroundStyle(.silver)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Feature-internal pushes from Learn.
enum LearnRoute: Hashable {
    case cards
    case drill
}

#Preview {
    NavigationStack { LearnView().appRouteDestinations() }
        .previewEnvironment()
}
