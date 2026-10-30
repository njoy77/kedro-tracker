import SwiftUI

/// The Table's toolbar title (design §6): "ROUND 6 OF 6" over the metadata line
/// "COLD DECK · NOAH DEALS". When the line doesn't fit between the toolbar's buttons (a long table
/// word or name on a narrow phone), the table word and the dealer each get a line of their own
/// rather than being cut off.
struct TableToolbarTitle: View {
    let round: String
    let word: String
    /// The dealer's display name; nil before anyone deals.
    let dealer: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            VStack(spacing: 1) {
                roundLine
                if let dealer {
                    metadata(Literal.deals(word: word, dealer: dealer))
                }
            }
            VStack(spacing: 0) {
                roundLine
                metadata(word.uppercased())
                if let dealer {
                    metadata(TableText.text("label.dealer", ["name": dealer.uppercased()]))
                }
            }
            .minimumScaleFactor(0.8)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dealer.map { "\(round), \(Literal.deals(word: word, dealer: $0))" } ?? round)
    }

    private var roundLine: some View {
        Text(round)
            .kedroFont(.label)
            .foregroundStyle(.cream)
    }

    private func metadata(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.silver)
    }
}

#Preview("Fits on one line") {
    NavigationStack {
        Color.night
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TableToolbarTitle(round: "ROUND 6 OF 6", word: "Cold Deck", dealer: "Noah")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Long word and name") {
    NavigationStack {
        Color.night
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Minimize", systemImage: "chevron.down") {} }
                ToolbarItem(placement: .principal) {
                    TableToolbarTitle(round: "ROUND 6 OF 8", word: "Corner Booth", dealer: "Maximilian")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("History", systemImage: "clock.arrow.circlepath") {}
                    Button("End Game", systemImage: "flag.checkered") {}
                    Button("More", systemImage: "ellipsis") {}
                }
            }
            .navigationBarTitleDisplayMode(.inline)
    }
}
