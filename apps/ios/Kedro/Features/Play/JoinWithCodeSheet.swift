import SwiftUI

/// Join with Code (design §5.9 #6): type the table's two-word name when proximity fails.
/// Matches the nearby tables by table word; admission is Ask to Sit unless you've played with
/// the host.
struct JoinWithCodeSheet: View {
    let model: PlayModel

    @Environment(\.dismiss) private var dismiss
    @State private var word = ""
    @State private var problem: String?
    @FocusState private var isFocused: Bool

    private var isKnownWord: Bool {
        let typed = TableWord.normalized(word)
        return TableWord.all.contains { TableWord.normalized($0) == typed }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Cold Deck", text: $word)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.join)
                        .focused($isFocused)
                        .onSubmit(join)
                        .accessibilityLabel("Table word")
                } header: {
                    Text("The table's two words")
                } footer: {
                    Text(problem ?? "It's at the top of the host's Table, like COLD DECK or LAST CALL.")
                }
            }
            .navigationTitle(Literal.text("button.joinWithCode"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Find", action: join)
                        .disabled(TableWord.normalized(word).split(separator: " ").count < 2)
                }
            }
            .onAppear { isFocused = true }
            .onChange(of: word) { problem = nil }
        }
        .presentationDetents([.medium])
    }

    private func join() {
        if let table = model.table(matching: word) {
            model.showCard(for: table)
            dismiss()
        } else if !isKnownWord {
            problem = "That's not a table word. They're two words from the host's screen, like Cold Deck."
        } else {
            // TODO(networking): look the word up online (Supabase) when it isn't visible nearby.
            problem = "No table called \(word.trimmingCharacters(in: .whitespaces)) nearby. Move closer, or scan the host's QR code."
        }
    }
}

#Preview {
    Color.night
        .sheet(isPresented: .constant(true)) {
            JoinWithCodeSheet(model: PlayModel(app: .preview()))
        }
        .previewEnvironment()
}
