import SwiftUI

/// The body of the Round sheet (mockup frame 8): who knocked, the player rows, the verdict line,
/// the number pad (or Card mode), and Cards + Next/Save. Shared by recording and corrections.
struct RoundEntryPanel<Footer: View>: View {
    @Binding var entry: RoundEntry
    @Binding var isCardMode: Bool
    let seats: [Seat]
    /// "Save Round 6" or "Save Change".
    let saveTitle: String
    var isSaving = false
    let onSave: () -> Void
    @ViewBuilder var footer: Footer

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            knockerSection
            Divider().overlay(.rule).padding(.horizontal, 16)
            if dynamicTypeSize.isAccessibilitySize {
                singleRowHeader
            } else {
                rowsList
            }
            footer
            verdictLine
            inputArea
                .padding(.horizontal, 12)
            actionRow
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)
        }
    }

    // MARK: Knocker

    private var knockerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(TableText.text("label.whoKnocked"))
                    .kedroFont(.label)
                    .foregroundStyle(.silver)
                if case .liveKnock(let name) = entry.knockerSource {
                    Text("· " + TableText.text("label.markedLive", ["name": name]))
                        .font(.caption2)
                        .foregroundStyle(.silverDim)
                }
            }
            .padding(.horizontal, 16)
            SeatPickerRow(seats: seats, selected: entry.knocker, marksKnocker: true) { seat in
                entry.selectKnocker(seat)
            }
            if entry.knocker != nil {
                Toggle(isOn: Binding(get: { entry.isInherent }, set: { entry.setInherent($0) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(TableText.text("label.inherentKnock"))
                            .font(.subheadline)
                            .foregroundStyle(.cream)
                        Text(TableText.text("label.inherentKnockHint"))
                            .font(.caption2)
                            .foregroundStyle(.silverDim)
                    }
                }
                .tint(.kedroRed)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Rows

    private var rowsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(entry.rows, id: \.self) { seatID in
                        if let seat = seats.first(where: { $0.id == seatID }) {
                            EntryRow(
                                seat: seat,
                                entry: entry.entry(seatID),
                                preview: entry.previewScore(seatID),
                                isKnocker: entry.knocker == seatID,
                                isFocused: entry.focus == seatID
                            ) {
                                entry.setFocus(seatID)
                            }
                            .id(seatID)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: entry.focus) { _, focus in
                guard let focus else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(focus, anchor: .center) }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: entry.rows)
    }

    /// At accessibility sizes the rows collapse to one player with ‹ › (design §14).
    private var singleRowHeader: some View {
        HStack(spacing: 8) {
            Button("Previous player", systemImage: "chevron.left") {
                if let previous = entry.neighbor(of: entry.focus, step: -1) { entry.setFocus(previous) }
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(entry.neighbor(of: entry.focus, step: -1) == nil)
            if let focus = entry.focus, let seat = seats.first(where: { $0.id == focus }) {
                EntryRow(seat: seat, entry: entry.entry(focus), preview: entry.previewScore(focus), isKnocker: entry.knocker == focus, isFocused: true) {}
            }
            Button("Next player", systemImage: "chevron.right") {
                if let next = entry.neighbor(of: entry.focus, step: 1) { entry.setFocus(next) }
            }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .disabled(entry.neighbor(of: entry.focus, step: 1) == nil)
        }
        .foregroundStyle(.cream)
        .padding(.horizontal, 8)
    }

    // MARK: Verdict

    @ViewBuilder
    private var verdictLine: some View {
        Group {
            if let verdict = entry.verdict {
                let text = verdict.text { seat in seats.first { $0.id == seat }?.displayName ?? "Someone" }
                verdictText(text)
            } else if entry.knocker == nil, entry.isComplete {
                Text(TableText.text("label.pickKnocker"))
                    .foregroundStyle(.silver)
            } else {
                Text(" ")
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// "**Sam knocked on 1** · lowest at the table · landed −10".
    private func verdictText(_ text: String) -> Text {
        guard let split = text.range(of: " · ") else { return Text(text).foregroundStyle(.cream) }
        let head = String(text[..<split.lowerBound])
        let rest = String(text[split.lowerBound...])
        return Text("\(Text(head).bold().foregroundStyle(.cream))\(Text(rest).foregroundStyle(.silver))")
    }

    // MARK: Input

    @ViewBuilder
    private var inputArea: some View {
        if isCardMode {
            VStack(spacing: 8) {
                HStack {
                    Text(entry.focus.map { entry.entry($0).trayText ?? TableText.text("label.cardsEmpty") } ?? "")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.cream)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Remove last card", systemImage: "delete.left") {
                        entry.removeLastCard()
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.silver)
                    .frame(minWidth: 44, minHeight: 44)
                }
                CardPalette(redKingsLeft: entry.redKingsLeftForFocus) { card in
                    entry.add(card)
                }
            }
        } else {
            NumberPad { key in entry.press(key) }
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(isCardMode ? TableText.text("button.pad") : Literal.text("button.cards")) {
                isCardMode.toggle()
            }
            .buttonStyle(.kedroGlass)
            .frame(width: 104)
            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch entry.primaryAction {
        case .next(let seatID):
            Button(Literal.next(seats.first { $0.id == seatID }?.displayName ?? "")) {
                entry.advance()
            }
            .buttonStyle(.kedroPrimary)
        case .save:
            Button(saveTitle, action: onSave)
                .buttonStyle(.kedroPrimary)
                .disabled(!entry.canSave || !entry.hasChanges || isSaving)
        }
    }
}

extension RoundEntryPanel where Footer == EmptyView {
    init(entry: Binding<RoundEntry>, isCardMode: Binding<Bool>, seats: [Seat], saveTitle: String, isSaving: Bool = false, onSave: @escaping () -> Void) {
        self.init(entry: entry, isCardMode: isCardMode, seats: seats, saveTitle: saveTitle, isSaving: isSaving, onSave: onSave) { EmptyView() }
    }
}

/// One player row: avatar, name (with "✋ knocked"), the value as typed, and "→ −10".
struct EntryRow: View {
    let seat: Seat
    let entry: HandEntry
    let preview: Int?
    let isKnocker: Bool
    let isFocused: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                AvatarView(seat: seat, size: .compact)
                HStack(spacing: 6) {
                    Text(seat.displayName)
                        .foregroundStyle(.cream)
                        .lineLimit(1)
                    if isKnocker {
                        Label(TableText.text("label.knocked"), systemImage: "hand.raised.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.kedroRed)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                valueBox
                Text(preview.map { "→ " + ScoreFormat.string($0) } ?? "")
                    .font(.footnote.weight(isKnocker ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(.silver)
                    .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .accessibilityHint("Enter this player's hand")
    }

    private var valueBox: some View {
        HStack(spacing: 1) {
            Text(entry.display)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.cream)
            if isFocused {
                Capsule()
                    .fill(.kedroRed)
                    .frame(width: 2, height: 20)
                    .phaseAnimator([1.0, 0.0]) { caret, opacity in caret.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.5) }
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: 64, minHeight: 36)
        .padding(.horizontal, 4)
        .background(.surfaceRaised, in: .rect(cornerRadius: 10))
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 10).strokeBorder(.kedroRed, lineWidth: 2)
            }
        }
    }

    private var accessibilityText: String {
        var parts = [seat.displayName]
        if isKnocker { parts.append("knocked") }
        if let value = entry.value {
            parts.append("hand \(ScoreFormat.spoken(value))")
            if let preview, preview != value { parts.append("scores \(ScoreFormat.spoken(preview))") }
        } else {
            parts.append("no hand yet")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Entering Round 6") {
    @Previewable @State var entry: RoundEntry = {
        var entry = RoundEntry(roundNumber: 6, seats: PreviewData.sampleSeats.map(\.id), liveKnock: PreviewData.sampleState(throughRound: 5).liveKnock)
        entry.selectKnocker(PreviewData.samSeat)
        for key in [PadKey.digit(1)] { entry.press(key) }
        entry.advance()
        entry.press(.digit(7))
        entry.advance()
        entry.press(.digit(2))
        return entry
    }()
    @Previewable @State var cards = false
    RoundEntryPanel(entry: $entry, isCardMode: $cards, seats: PreviewData.sampleSeats, saveTitle: Literal.saveRound(6)) {}
        .background(.surface)
        .previewEnvironment()
}
