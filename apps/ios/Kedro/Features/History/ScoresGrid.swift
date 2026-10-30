import SwiftUI

/// A cell in the scores grid.
struct ScoreCellRef: Identifiable, Hashable {
    var round: Int
    var seat: SeatID

    var id: String { "\(round)|\(seat.rawValue)" }
}

/// History's Scores tab (design §9.1, mockup frame 11): rounds × players, the knocker's cell marked
/// ✓ / = / ✗ (solid, outline, hatched), ✎ on edited values, totals pinned underneath. Scrolls
/// horizontally at 6–8 players; becomes a per-round list at accessibility sizes. VoiceOver gets
/// Rounds, Edited and Knocks rotors.
struct ScoresGrid: View {
    let state: GameState
    var canEdit = false
    var onTap: (ScoreCellRef) -> Void = { _ in }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var rotor

    static let roundColumn: CGFloat = 34
    static let compactColumn: CGFloat = 54

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            roundList
        } else {
            grid
        }
    }

    private var isCompact: Bool { state.seats.count >= StandingsView.compactThreshold }

    // MARK: Grid

    private var grid: some View {
        let table = VStack(spacing: 0) {
            header
            Divider().overlay(.rule)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(state.rounds) { record in
                        row(record)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider().overlay(.rule)
            totals
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .accessibilityRotor(TableText.text("label.rotorRounds")) {
            ForEach(roundCells) { cell in
                AccessibilityRotorEntry(Text(TableText.text("label.roundRow", ["r": cell.round])), id: cell.id, in: rotor)
            }
        }
        .accessibilityRotor(TableText.text("label.rotorEdited")) {
            ForEach(editedCells) { cell in
                AccessibilityRotorEntry(Text(cellLabel(cell)), id: cell.id, in: rotor)
            }
        }
        .accessibilityRotor(TableText.text("label.rotorKnocks")) {
            ForEach(state.rounds) { record in
                let cell = ScoreCellRef(round: record.number, seat: record.knocker)
                AccessibilityRotorEntry(Text(cellLabel(cell)), id: cell.id, in: rotor)
            }
        }

        return Group {
            if isCompact {
                ScrollView(.horizontal) { table }
                    .scrollIndicators(.visible)
            } else {
                table
            }
        }
        .background(.surface, in: .rect(cornerRadius: 18))
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(TableText.text("label.rd"))
                .kedroFont(.label)
                .foregroundStyle(.silverDim)
                .frame(width: Self.roundColumn, alignment: .leading)
                .padding(.leading, 4)
            ForEach(state.seats) { seat in
                Text(seat.displayName)
                    .kedroFont(.label)
                    .foregroundStyle(.silver)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .modifier(ColumnWidth(compact: isCompact))
            }
        }
        .padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private func row(_ record: RoundRecord) -> some View {
        HStack(spacing: 0) {
            Text(String(record.number))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.silverDim)
                .frame(width: Self.roundColumn, alignment: .leading)
                .padding(.leading, 4)
                .accessibilityHidden(true)
            ForEach(state.seats) { seat in
                let ref = ScoreCellRef(round: record.number, seat: seat.id)
                Button {
                    onTap(ref)
                } label: {
                    ScoreCell(record: record, seat: seat.id)
                        .modifier(ColumnWidth(compact: isCompact))
                        .frame(minHeight: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!canEdit || record.scores[seat.id] == nil)
                .accessibilityLabel(cellLabel(ref))
                .accessibilityHint(canEdit ? TableText.text("label.cellHint") : "")
                .accessibilityRotorEntry(id: ref.id, in: rotor)
            }
        }
    }

    private var totals: some View {
        HStack(spacing: 0) {
            Text(TableText.text("label.tot"))
                .kedroFont(.label)
                .foregroundStyle(.silver)
                .frame(width: Self.roundColumn, alignment: .leading)
                .padding(.leading, 4)
            ForEach(state.seats) { seat in
                let standing = state.standing(for: seat.id)
                ScoreText(value: standing?.total ?? 0, style: .scoreCompact)
                    .foregroundStyle(standing?.isLeader == true && !state.rounds.isEmpty ? Color.gold : Color.cream)
                    .modifier(ColumnWidth(compact: isCompact))
                    .accessibilityLabel("\(seat.displayName), total \(ScoreFormat.spoken(standing?.total ?? 0))")
            }
        }
        .padding(.top, 8)
    }

    // MARK: Accessibility list

    private var roundList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(state.rounds) { record in
                VStack(alignment: .leading, spacing: 6) {
                    Text(TableText.text("label.roundRow", ["r": record.number]))
                        .kedroFont(.headline)
                        .foregroundStyle(.cream)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(state.seats) { seat in
                        let ref = ScoreCellRef(round: record.number, seat: seat.id)
                        Button {
                            onTap(ref)
                        } label: {
                            HStack {
                                Text(seat.displayName).foregroundStyle(.cream)
                                Spacer()
                                ScoreCell(record: record, seat: seat.id)
                            }
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canEdit || record.scores[seat.id] == nil)
                        .accessibilityLabel(cellLabel(ref))
                        .accessibilityHint(canEdit ? TableText.text("label.cellHint") : "")
                    }
                }
                .padding(14)
                .background(.surface, in: .rect(cornerRadius: 18))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(TableText.text("label.tot"))
                    .kedroFont(.headline)
                    .foregroundStyle(.cream)
                ForEach(state.standings) { standing in
                    HStack {
                        Text(standing.seat.displayName).foregroundStyle(.cream)
                        Spacer()
                        ScoreText(value: standing.total, style: .scoreCompact)
                            .foregroundStyle(standing.isLeader ? Color.gold : Color.cream)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(14)
            .background(.surface, in: .rect(cornerRadius: 18))
        }
    }

    // MARK: Labels

    /// The first cell of each round, for the Rounds rotor.
    private var roundCells: [ScoreCellRef] {
        guard let first = state.seats.first?.id else { return [] }
        return state.rounds.map { ScoreCellRef(round: $0.number, seat: first) }
    }

    private var editedCells: [ScoreCellRef] {
        state.rounds.flatMap { record in
            state.seats.filter { record.editedSeats.contains($0.id) }.map { ScoreCellRef(round: record.number, seat: $0.id) }
        }
    }

    /// "Round 4, Sam, minus 1, edited" / "Round 3, Noah, 18, knocked, failed".
    private func cellLabel(_ ref: ScoreCellRef) -> String {
        guard let record = state.round(ref.round) else { return "" }
        var parts = [TableText.text("label.roundRow", ["r": ref.round]), state.name(of: ref.seat)]
        if let score = record.scores[ref.seat] { parts.append(ScoreFormat.spoken(score)) }
        if record.knocker == ref.seat, let outcome = record.outcome {
            parts.append(TableText.text("label.knockerCell", ["outcome": outcome.word]))
        }
        if record.editedSeats.contains(ref.seat) { parts.append(TableText.text("label.edited").lowercased()) }
        return parts.joined(separator: ", ")
    }
}

/// One cell: the round score; the knocker's in an outcome badge; ✎ if edited.
struct ScoreCell: View {
    let record: RoundRecord
    let seat: SeatID

    var body: some View {
        let score = record.scores[seat] ?? 0
        HStack(spacing: 2) {
            if record.scores[seat] == nil {
                // A late joiner, before their first round.
                Text("–")
                    .font(.subheadline)
                    .foregroundStyle(.silverDim)
            } else if record.knocker == seat, let outcome = record.outcome {
                KnockScoreBadge(score: score, outcome: outcome)
            } else {
                Text(ScoreFormat.string(score))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.cream)
            }
            if record.editedSeats.contains(seat) {
                Image(systemName: "pencil")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.kedroRed)
            }
        }
    }
}

/// "−10 ✓" solid cream (landed), "5 =" outline (tied), "18 ✗" hatched (failed), design §3.6.
struct KnockScoreBadge: View {
    let score: Int
    let outcome: KnockOutcome

    var body: some View {
        HStack(spacing: 2) {
            Text(ScoreFormat.string(score)).monospacedDigit()
            Image(systemName: outcome.systemImage).font(.caption2.weight(.heavy))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(outcome == .landed ? Color.night : Color.cream)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            switch outcome {
            case .landed:
                Capsule().fill(.cream)
            case .tied:
                Capsule().strokeBorder(.silver, lineWidth: 1.5)
            case .failed:
                HatchPattern(color: .silverDim, spacing: 5, lineWidth: 2)
                    .clipShape(.capsule)
                    .overlay { Capsule().strokeBorder(.silverDim, lineWidth: 1) }
            }
        }
        .fixedSize()
    }
}

/// Columns share the width at 3–5 players and are fixed (scrolling) at 6–8.
private struct ColumnWidth: ViewModifier {
    let compact: Bool

    func body(content: Content) -> some View {
        if compact {
            content.frame(width: ScoresGrid.compactColumn)
        } else {
            content.frame(maxWidth: .infinity)
        }
    }
}

#Preview("5 players") {
    ScoresGrid(state: PreviewData.sampleState(throughRound: 5), canEdit: true)
        .padding()
        .background(.night)
        .previewEnvironment()
}

#Preview("8 players") {
    ScoresGrid(state: TablePreviews.eightPlayerState, canEdit: true)
        .padding()
        .background(.night)
        .previewEnvironment()
}
