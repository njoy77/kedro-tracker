import SwiftUI

/// A correction (design §9.2): History → tap the cell → the number pad with the old value → Save
/// Change. Four taps. The footer lists "What changes" under H-01; changing the knocker or
/// flipping a knock outcome asks first ("Everyone sees this.").
struct CorrectionSheet: View {
    let session: GameSession
    let roundNumber: Int

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var entry: RoundEntry
    @State private var isCardMode = false
    @State private var typoFlag: TypoGuard.Flag?
    @State private var pendingConfirmation: String?
    @State private var isSaving = false
    @State private var saves = 0

    init(session: GameSession, roundNumber: Int, focus: SeatID?) {
        self.session = session
        self.roundNumber = roundNumber
        let seats = session.state.seats(inRound: roundNumber).map(\.id)
        if let record = session.state.round(roundNumber) {
            _entry = State(initialValue: RoundEntry(editing: record.round, seats: seats, focus: focus))
        } else {
            _entry = State(initialValue: RoundEntry(roundNumber: roundNumber, seats: seats))
        }
    }

    var body: some View {
        let state = session.state
        NavigationStack {
            RoundEntryPanel(
                entry: $entry,
                isCardMode: $isCardMode,
                seats: state.seats(inRound: roundNumber),
                saveTitle: Literal.text("button.saveChange"),
                isSaving: isSaving,
                onSave: save
            ) {
                whatChanges
            }
            .background(.surface)
            .navigationTitle(TableText.text("label.fixRound", ["r": roundNumber]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TableText.text("button.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
        .sensoryFeedback(.success, trigger: saves)
        .onChange(of: state.status.isLive) { _, live in
            if !live { dismiss() }
        }
        .alert(typoTitle, isPresented: isShowingTypo, presenting: typoFlag) { flag in
            Button(Literal.keepHand(flag.hand)) { confirmThenCommit() }
            Button(Literal.fix(state.name(of: flag.seat)), role: .cancel) { entry.fix(flag.seat) }
        }
        .alert(Literal.text("button.saveChange"), isPresented: isConfirming, presenting: pendingConfirmation) { _ in
            Button(Literal.text("button.saveChange")) { commit() }
            Button(TableText.text("button.cancel"), role: .cancel) {}
        } message: { text in
            Text(text)
        }
    }

    // MARK: What changes

    private var preview: CorrectionPreview? {
        guard let round = entry.round, entry.hasChanges else { return nil }
        let after = session.preview(.roundEdited(.init(round: round)))
        return CorrectionPreview(before: session.state, after: after, roundNumber: roundNumber)
    }

    @ViewBuilder
    private var whatChanges: some View {
        let state = session.state
        VStack(alignment: .leading, spacing: 4) {
            if let preview, !preview.isEmpty {
                Text(app.houseVoice(for: state).line("H-01"))
                    .kedroFont(.label)
                    .foregroundStyle(.silver)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(preview.lines) { line in
                            Text(preview.text(for: line, name: state.name(of:)))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.cream)
                        }
                        if let outcome = preview.outcome {
                            Text(TableText.text("label.knockFlip", [
                                "knocker": preview.knockerSeat.map(state.name(of:)) ?? "Someone",
                                "before": outcome.before.word, "after": outcome.after.word,
                            ]))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.kedroRed)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 84)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                Text(TableText.text("label.noChange"))
                    .font(.footnote)
                    .foregroundStyle(.silverDim)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.surfaceRaised, in: .rect(cornerRadius: 14))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    // MARK: Saving

    private var isShowingTypo: Binding<Bool> {
        Binding(get: { typoFlag != nil }, set: { if !$0 { typoFlag = nil } })
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { pendingConfirmation != nil }, set: { if !$0 { pendingConfirmation = nil } })
    }

    private var typoTitle: Text {
        guard let typoFlag else { return Text(verbatim: "") }
        let state = session.state
        return Text(app.houseVoice(for: state).line("K-11", ["name": state.name(of: typoFlag.seat), "hand": typoFlag.hand]))
    }

    private func save() {
        guard entry.canSave, entry.hasChanges else { return }
        if let flag = entry.typoCheck() {
            typoFlag = flag
            return
        }
        confirmThenCommit()
    }

    private func confirmThenCommit() {
        if let preview, preview.needsConfirmation, let text = preview.confirmationText(name: session.state.name(of:)) {
            pendingConfirmation = text
        } else {
            commit()
        }
    }

    private func commit() {
        guard let round = entry.round, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await session.editRound(round.number, hands: round.hands, knocker: round.knocker)
                saves += 1
                dismiss()
            } catch {
                app.toasts.show(error.localizedDescription)
            }
        }
    }
}

#Preview("Fix Round 4") {
    Color.night
        .sheet(isPresented: .constant(true)) {
            CorrectionSheet(session: PreviewData.sampleSession(throughRound: 5), roundNumber: 4, focus: PreviewData.samSeat)
        }
        .previewEnvironment()
}
