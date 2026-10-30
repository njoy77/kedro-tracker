import SwiftUI

/// Report Your Hand (design §7.4): the I knocked toggle, the pad (or Cards), Submit. A phone
/// reports its own seat and any guest it's the reporter for. Values stay hidden until everyone has
/// reported; then the round saves itself and every phone reveals it together.
struct ReportHandSheet: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.dismiss) private var dismiss
    @State private var roundNumber: Int
    @State private var current: SeatID?
    @State private var entry = HandEntry.empty
    @State private var knocked = false
    /// Went out with all four cards (an inherent knock: hand 0).
    @State private var wentOut = false
    @State private var isCardMode = false
    @State private var isSubmitting = false
    @State private var submits = 0
    @State private var detent: PresentationDetent = .large

    init(session: GameSession) {
        self.session = session
        _roundNumber = State(initialValue: session.state.nextRoundNumber)
    }

    var body: some View {
        let state = session.state
        NavigationStack {
            Group {
                if let me = session.mySeatID {
                    if let current, state.status.isLive {
                        reportForm(for: current, mine: GuestReporters.seats(reportedBy: me, in: state.seats))
                    } else {
                        waiting
                    }
                } else {
                    ContentUnavailableView(TableText.text("label.watching"), systemImage: "eye")
                }
            }
            .background(.surface)
            .navigationTitle(TableText.text("label.round", ["r": roundNumber]))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TableText.text(current == nil ? "button.close" : "button.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: submits)
        .onAppear {
            isCardMode = prefs.prefersCardMode ?? (session.mySeat?.isLearner ?? false)
            current = nextPending()
            detent = current == nil ? .medium : .large
        }
        .onChange(of: isCardMode) { _, cards in prefs.prefersCardMode = cards }
        .onChange(of: state.nextRoundNumber) { _, next in
            // Everyone's in and the knocker's settled: the round saved itself.
            if next != roundNumber { dismiss() }
        }
    }

    // MARK: Form

    private func reportForm(for seatID: SeatID, mine: [SeatID]) -> some View {
        let state = session.state
        return VStack(spacing: 12) {
            if mine.count > 1 {
                Picker(TableText.text("label.reportingFor"), selection: Binding(get: { seatID }, set: { switchTo($0) })) {
                    ForEach(mine, id: \.self) { seat in
                        let reported = state.selfReport?.hands[seat] != nil
                        Text(state.name(of: seat) + (reported ? " ✓" : "")).tag(seat)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
            }
            Toggle(isOn: $knocked) {
                Label(TableText.text("label.iKnocked"), systemImage: "hand.raised.fill")
                    .foregroundStyle(.cream)
            }
            .tint(.kedroRed)
            .padding(.horizontal, 16)
            .onChange(of: knocked) { _, on in if !on { wentOut = false } }
            if knocked {
                Toggle(isOn: $wentOut) {
                    Text(TableText.text("label.inherentKnock")).foregroundStyle(.cream)
                }
                .tint(.kedroRed)
                .padding(.horizontal, 16)
                .onChange(of: wentOut) { _, on in if on { entry = HandEntry(value: 0) } }
            }

            HStack {
                if let seat = state.seat(seatID) { AvatarView(seat: seat, size: .compact) }
                Text(state.name(of: seatID)).foregroundStyle(.cream)
                Spacer()
                Text(isCardMode ? (entry.trayText ?? TableText.text("label.cardsEmpty")) : entry.display)
                    .font(isCardMode ? .subheadline.monospacedDigit() : .system(.title, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.cream)
                    .frame(minWidth: 72, minHeight: 44, alignment: .trailing)
                    .padding(.horizontal, 10)
                    .background(.surfaceRaised, in: .rect(cornerRadius: 10))
                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.kedroRed, lineWidth: 2) }
                    .accessibilityLabel(entry.value.map { "Hand \(ScoreFormat.spoken($0))" } ?? "No hand yet")
            }
            .padding(.horizontal, 16)

            Group {
                if isCardMode {
                    CardPalette(redKingsLeft: redKingsLeft(for: seatID) - entry.redKings) { card in
                        var next = entry
                        if case .typed = next { next = .empty }
                        guard next.add(card, redKingsLeft: redKingsLeft(for: seatID) - next.redKings) else { return false }
                        entry = next
                        return true
                    }
                } else {
                    NumberPad { key in entry.press(key, negativeLimit: redKingsLeft(for: seatID)) }
                }
            }
            .padding(.horizontal, 12)

            HStack(spacing: 8) {
                Button(isCardMode ? TableText.text("button.pad") : Literal.text("button.cards")) { isCardMode.toggle() }
                    .buttonStyle(.kedroGlass)
                    .frame(width: 104)
                Button(TableText.text("button.submit")) { submit(seatID) }
                    .buttonStyle(.kedroPrimary)
                    .disabled(entry.value == nil || isSubmitting)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            Text(TableText.text("label.valuesHidden"))
                .font(.caption)
                .foregroundStyle(.silverDim)
        }
        .padding(.top, 8)
    }

    // MARK: Waiting

    private var waiting: some View {
        let state = session.state
        let resolution = KnockerResolution.evaluate(state.selfReport, seats: state.seats.map(\.id), now: .now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if case .collecting(let waitingOn) = resolution {
                    Text(app.houseVoice(for: state).line("K-14", ["names": ListFormatter.localizedString(byJoining: waitingOn.map(state.name(of:)))]))
                        .font(.callout)
                        .foregroundStyle(.cream)
                }
                ForEach(state.seats) { seat in
                    let reported = state.selfReport?.hands[seat.id] != nil
                    HStack(spacing: 10) {
                        AvatarView(seat: seat, size: .compact)
                        Text(seat.displayName).foregroundStyle(.cream)
                        Spacer()
                        if reported {
                            Label(TableText.text("label.reported"), systemImage: "checkmark")
                                .font(.footnote)
                                .foregroundStyle(.silver)
                        } else {
                            Text("…").foregroundStyle(.silverDim)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if resolution.needsDecision {
                    KnockerDecisionView(session: session)
                }
                Text(TableText.text("label.valuesHidden"))
                    .font(.caption)
                    .foregroundStyle(.silverDim)
            }
            .padding(16)
        }
    }

    // MARK: Actions

    private func nextPending() -> SeatID? {
        guard let me = session.mySeatID else { return nil }
        let reported = session.state.selfReport?.hands ?? [:]
        return GuestReporters.seats(reportedBy: me, in: session.state.seats).first { reported[$0] == nil }
    }

    private func switchTo(_ seat: SeatID) {
        current = seat
        entry = session.state.selfReport?.hands[seat].map(HandEntry.init(value:)) ?? .empty
        knocked = session.state.selfReport?.claimedKnockers.contains(seat) ?? false
        wentOut = false
    }

    /// Red Kings not already in hands reported by others (a lower bound: only negatives show).
    private func redKingsLeft(for seat: SeatID) -> Int {
        let others = (session.state.selfReport?.hands ?? [:]).filter { $0.key != seat }
        let used = others.values.reduce(0) { $0 + max(0, -$1) }
        return max(0, CardFace.redKingsPerDeck - used)
    }

    private func submit(_ seat: SeatID) {
        guard let value = entry.value else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await session.reportHand(value, knocked: knocked, inherent: wentOut && value == 0, for: seat)
                submits += 1
                entry = .empty
                knocked = false
                wentOut = false
                current = nextPending()
                if current == nil { detent = .medium }
            } catch {
                app.toasts.show(error.localizedDescription)
            }
        }
    }
}

#Preview("Report") {
    Color.night
        .sheet(isPresented: .constant(true)) {
            ReportHandSheet(session: TablePreviews.selfReportSession(reported: 0))
        }
        .previewEnvironment()
}

#Preview("Waiting") {
    Color.night
        .sheet(isPresented: .constant(true)) {
            ReportHandSheet(session: TablePreviews.selfReportSession(reported: 3))
        }
        .previewEnvironment()
}
