import SwiftUI

/// The Rules reference (design §13.1): the whole canonical ruleset as a searchable `List`,
/// literal in every level, with the Knock Calculator one tap away.
///
/// A route destination (`AppRoute.rules`), so it doesn't create a NavigationStack. Mid-game,
/// present it with `.rulesSheet(isPresented:)`, which wraps it in a stack at `.medium`.
struct RulesSheet: View {
    @State private var query = ""

    private var sections: [RuleSection] { RulesContent.search(query) }

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    NavigationLink(value: AppRoute.knockCalculator(nil)) {
                        Label("Knock Calculator", systemImage: "function")
                    }
                } footer: {
                    Text("Type in the hands and the knocker to see exactly how a round scores.")
                }
            }
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.rules) { rule in
                        Text(rule.text)
                            .font(.callout)
                            .foregroundStyle(.cream)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
        .overlay {
            if sections.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search the rules")
        .navigationTitle("Rules")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    /// The Rules reference as a `.medium` sheet (mid-game, design §13.1), with its own stack so
    /// the Knock Calculator can push.
    func rulesSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                RulesSheet()
                    .appRouteDestinations()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Literal.text("button.done")) { isPresented.wrappedValue = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

#Preview {
    NavigationStack { RulesSheet().appRouteDestinations() }
        .previewEnvironment()
}

#Preview("As a sheet") {
    Color.night
        .rulesSheet(isPresented: .constant(true))
        .previewEnvironment()
}
