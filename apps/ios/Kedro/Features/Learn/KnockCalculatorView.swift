import SwiftUI

// STUB: owned by lobby. Replace this file's contents; keep the type name and initializer.

/// The Knock Calculator, prefilled from a round's Why? (design §13.1).
struct KnockCalculatorView: View {
    let prefill: Round?

    var body: some View {
        ContentUnavailableView(
            "Knock Calculator",
            systemImage: "function",
            description: Text("Coming soon.")
        )
        .navigationTitle("Knock Calculator")
    }
}

#Preview {
    NavigationStack { KnockCalculatorView(prefill: PreviewData.sampleRounds[4]) }.previewEnvironment()
}
