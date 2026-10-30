import SwiftUI

/// Canned taunts only (design §5.8): pick who it's for, then a line. Custom taunts need the
/// full app's filter, report and block flow (§8.3), so the clip doesn't offer them. Canned
/// taunts travel as copy IDs and render in each recipient's own level.
struct ClipTauntSheet: View {
    @Environment(ClipModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let state: GameState

    @State private var target: TauntTarget = .table

    private var others: [Seat] { state.seats.filter { $0.id != model.mySeat } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(Literal.text("button.talk"), selection: $target) {
                        Text(ClipCopy.everyone).tag(TauntTarget.table)
                        ForEach(others) { seat in
                            Text(seat.displayName).tag(TauntTarget.seat(seat.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                ForEach(TauntGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(group.tauntIDs, id: \.self) { id in
                            Button {
                                Task {
                                    await model.sendTaunt(id, to: target)
                                    dismiss()
                                }
                            } label: {
                                Text(model.voice.line(id))
                                    .foregroundStyle(.cream)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.night)
            .navigationTitle(Literal.text("button.talk"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Literal.text("button.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ClipTauntSheet(state: PreviewData.sampleState(throughRound: 5))
        .environment(ClipModel.preview(seated: true, throughRound: 5))
}
