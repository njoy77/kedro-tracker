import SwiftUI

/// Record a round (design §7): the number pad or Card mode in scorekeeper mode, Report Your Hand
/// in self-report mode, and the finish gate after the last planned round (§9.3).
///
/// Present as a `.sheet` (it sets its own detents). The Table sets `toasts.isDeferring` while it's
/// open, so nothing covers it; the "Round 6 saved · Undo" toast appears as it closes.
struct RoundSheet: View {
    let session: GameSession
    /// "Fix a Round First" on the finish gate: the Table opens History.
    var onFixRound: (() -> Void)?

    init(session: GameSession, onFixRound: (() -> Void)? = nil) {
        self.session = session
        self.onFixRound = onFixRound
    }

    var body: some View {
        if session.state.config.scoringMode == .selfReport {
            if session.state.isAwaitingFinish {
                SelfReportFinishGateSheet(session: session, onFixRound: onFixRound)
            } else {
                ReportHandSheet(session: session)
            }
        } else {
            ScorekeeperRoundSheet(session: session, onFixRound: onFixRound)
        }
    }
}

/// Scorekeeper mode: knocker, rows, pad, Save (design §7.1–§7.3).
private struct ScorekeeperRoundSheet: View {
    let session: GameSession
    var onFixRound: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var entry: RoundEntry
    @State private var isCardMode: Bool
    @State private var typoFlag: TypoGuard.Flag?
    @State private var isSaving = false
    @State private var savedRounds = 0
    @State private var showsFinishGate: Bool
    @State private var errorMessage: String?

    init(session: GameSession, onFixRound: (() -> Void)?) {
        self.session = session
        self.onFixRound = onFixRound
        let state = session.state
        _entry = State(initialValue: RoundEntry(roundNumber: state.nextRoundNumber, seats: state.seats.map(\.id), liveKnock: state.liveKnock))
        _isCardMode = State(initialValue: false)
        _showsFinishGate = State(initialValue: state.isAwaitingFinish)
    }

    var body: some View {
        let state = session.state
        NavigationStack {
            Group {
                if showsFinishGate {
                    FinishGateView(session: session, onFixRound: {
                        dismiss()
                        onFixRound?()
                    }, onDone: { dismiss() })
                } else {
                    RoundEntryPanel(
                        entry: $entry,
                        isCardMode: $isCardMode,
                        seats: state.seats,
                        saveTitle: Literal.saveRound(entry.roundNumber),
                        isSaving: isSaving,
                        onSave: save
                    ) {
                        if state.nextRoundNumber != entry.roundNumber {
                            Text(TableText.text("label.alreadySaved", ["r": entry.roundNumber]))
                                .font(.footnote)
                                .foregroundStyle(.cream)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.surfaceRaised, in: .rect(cornerRadius: 12))
                                .padding(.horizontal, 16)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.silver)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .background(.surface)
            .navigationTitle(TableText.text("label.round", ["r": showsFinishGate ? state.rounds.count : entry.roundNumber]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(showsFinishGate ? TableText.text("button.close") : TableText.text("button.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
        .sensoryFeedback(.success, trigger: savedRounds)
        .onAppear {
            isCardMode = prefs.prefersCardMode ?? (session.mySeat?.isLearner ?? false)
        }
        .onChange(of: isCardMode) { _, cards in prefs.prefersCardMode = cards }
        .onChange(of: state.liveKnock) { _, mark in entry.applyLiveKnock(mark) }
        .alert(typoTitle, isPresented: isShowingTypo, presenting: typoFlag) { flag in
            Button(Literal.keepHand(flag.hand)) { commit() }
            Button(Literal.fix(state.name(of: flag.seat)), role: .cancel) { entry.fix(flag.seat) }
        }
    }

    private var isShowingTypo: Binding<Bool> {
        Binding(get: { typoFlag != nil }, set: { if !$0 { typoFlag = nil } })
    }

    /// K-11: "Sam had 52? That's a lot of cards."
    private var typoTitle: Text {
        guard let typoFlag else { return Text(verbatim: "") }
        let state = session.state
        return Text(app.houseVoice(for: state).line("K-11", ["name": state.name(of: typoFlag.seat), "hand": typoFlag.hand]))
    }

    private func save() {
        guard entry.canSave, session.state.nextRoundNumber == entry.roundNumber else { return }
        if let flag = entry.typoCheck() {
            typoFlag = flag
            return
        }
        commit()
    }

    private func commit() {
        guard let round = entry.round, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                guard let knocker = round.knocker else { return }
                try await session.recordRound(hands: round.hands, knocker: knocker, inherent: round.isInherentKnock)
                savedRounds += 1
                showSavedToast(round.number)
                if session.state.isAwaitingFinish {
                    withAnimation { showsFinishGate = true }
                } else {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// "Round 6 saved. · Undo" on the saving phone for 5 s (design §7.1).
    private func showSavedToast(_ number: Int) {
        let session = session
        let toasts = app.toasts
        let voice = app.houseVoice(for: session.state)
        toasts.show(Toast(
            message: voice.line("K-19", ["round": number]),
            action: Toast.Action(title: Literal.text("button.undo")) {
                Task {
                    guard session.state.lastRound?.number == number else { return }
                    do { try await session.undoLastRound() } catch { toasts.show(error.localizedDescription) }
                }
            },
            duration: .seconds(5)
        ))
    }
}

/// Self-report mode lands on the finish gate when the last planned round saves itself.
private struct SelfReportFinishGateSheet: View {
    let session: GameSession
    var onFixRound: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FinishGateView(session: session, onFixRound: {
                dismiss()
                onFixRound?()
            }, onDone: { dismiss() })
            .background(.surface)
            .navigationTitle(TableText.text("label.round", ["r": session.state.rounds.count]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TableText.text("button.close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// The finish gate (design §9.3, G-01): Finish Game, Fix a Round First, Play Another Round.
struct FinishGateView: View {
    let session: GameSession
    var onFixRound: () -> Void
    var onDone: () -> Void

    @Environment(AppModel.self) private var app
    @State private var isWorking = false

    var body: some View {
        let state = session.state
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            Text(Literal.roundOf(state.rounds.count, state.config.plannedRounds))
                .kedroFont(.label)
                .foregroundStyle(.silver)
            Text(app.houseVoice(for: state).line("G-01"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.cream)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer(minLength: 12)
            VStack(spacing: 10) {
                Button(Literal.text("button.finishGame")) {
                    run { try await session.finish(reason: .completed) }
                }
                .buttonStyle(.kedroPrimary)
                Button(Literal.text("button.fixRoundFirst"), action: onFixRound)
                    .buttonStyle(.kedroGlassWide)
                Button(Literal.text("button.playAnotherRound")) {
                    run { try await session.extendRounds(by: 1) }
                }
                .buttonStyle(.kedroGlassWide)
            }
            .disabled(isWorking || !state.status.isLive)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await work()
                onDone()
            } catch {
                app.toasts.show(error.localizedDescription)
            }
        }
    }
}

#Preview("Record Round 6") {
    Color.night
        .sheet(isPresented: .constant(true)) {
            RoundSheet(session: PreviewData.sampleSession(throughRound: 5, liveKnock: true))
        }
        .previewEnvironment(AppModel.preview(liveGame: true))
}

#Preview("Finish gate") {
    Color.night
        .sheet(isPresented: .constant(true)) {
            RoundSheet(session: PreviewData.sampleSession(throughRound: 8, finished: false))
        }
        .previewEnvironment()
}

#Preview("Self-report") {
    Color.night
        .sheet(isPresented: .constant(true)) {
            RoundSheet(session: TablePreviews.selfReportSession(reported: 0))
        }
        .previewEnvironment()
}
