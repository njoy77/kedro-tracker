import SwiftUI

/// History's On the record tab (design §9.1–§9.2): every change, newest first, with who, when,
/// before → after and the downstream effect. Authors can Undo their own edits until the game
/// finishes. Duplicate rounds (H-06) offer "Use This Version".
struct OnTheRecordView: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @State private var isWorking = false

    var body: some View {
        let state = session.state
        let voice = app.houseVoice(for: state)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(state.conflicts) { conflict in
                conflictCard(conflict, voice: voice)
            }
            if state.audit.isEmpty {
                Text(voice.line("H-03"))
                    .font(.callout)
                    .foregroundStyle(.silver)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 32)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(state.audit.reversed().enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(.rule) }
                        AuditRow(entry: entry, state: state, voice: voice, canUndo: session.canUndo(entry) && !isWorking) {
                            run { try await session.undo(entry) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(.surface, in: .rect(cornerRadius: 18))
            }
        }
    }

    private func conflictCard(_ conflict: RoundConflict, voice: Voice) -> some View {
        let state = session.state
        let hands = state.seats(inRound: conflict.roundNumber).map { seat in
            "\(seat.displayName) \(ScoreFormat.string(conflict.rejected.hands[seat.id] ?? 0))"
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text(voice.line("H-06", ["r": conflict.roundNumber]))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.cream)
            Text(TableText.text("label.conflictBy", ["name": conflict.byName, "time": conflict.at.formatted(date: .omitted, time: .shortened)]))
                .font(.caption)
                .foregroundStyle(.silverDim)
            Text(hands.joined(separator: " · ") + " · " + TableText.text("label.knocked") + ": " + state.name(of: conflict.rejected.knocker))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.silver)
            if session.canEdit {
                Button(TableText.text("button.useThisVersion")) {
                    run { try await session.useConflictVersion(conflict) }
                }
                .buttonStyle(.kedroGlass)
                .disabled(isWorking)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.surfaceRaised, in: .rect(cornerRadius: 18))
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        let toasts = app.toasts
        Task {
            defer { isWorking = false }
            do { try await work() } catch { toasts.show(error.localizedDescription) }
        }
    }
}

/// "**Ben** changed Sam's R4 hand 1 → −1" over "9:41 · Cleo's knock still failed", with Undo for
/// the author.
struct AuditRow: View {
    let entry: AuditEntry
    let state: GameState
    let voice: Voice
    var canUndo = false
    var onUndo: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                summary
                    .font(.subheadline)
                    .foregroundStyle(.cream)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.silverDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if canUndo {
                Button(Literal.text("button.undo"), action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.kedroRed)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.vertical, 10)
    }

    /// The actor's name in bold, then the rest of the literal line. H-05 entries use the voice.
    private var summary: Text {
        if case .lateOperation(_, .afterFinish) = entry.change {
            return Text(voice.line("H-05", ["name": entry.actor.name]))
        }
        let line = entry.summary
        let name = entry.actor.name
        guard line.hasPrefix(name + " ") else { return Text(line) }
        return Text("\(Text(name).bold())\(String(line.dropFirst(name.count)))")
    }

    private var caption: String {
        let time = entry.at.formatted(date: .omitted, time: .shortened)
        guard let effect else { return time }
        return time + " · " + effect
    }

    /// The downstream effect: the knock's outcome, or who moved.
    private var effect: String? {
        switch entry.change {
        case let .roundEdited(round, _, knocker, outcome):
            guard let record = state.round(round) else { return nil }
            let knockerName = state.name(of: knocker?.after ?? record.knocker)
            if let outcome, let before = outcome.before, let after = outcome.after, before != after {
                return TableText.text("label.knockFlip", ["knocker": knockerName, "before": before.word, "after": after.word])
            }
            guard let current = record.outcome else { return nil }
            return TableText.text("label.knockStill", ["knocker": knockerName, "outcome": current.word])
        default:
            let moved = entry.effects.filter { $0.delta != 0 }
            guard !moved.isEmpty else { return nil }
            return moved.map { "\(state.name(of: $0.seat)) \(ScoreFormat.string($0.before)) → \(ScoreFormat.string($0.after))" }
                .joined(separator: ", ")
        }
    }
}

#Preview("On the record") {
    let session = PreviewData.sampleSession(throughRound: 5)
    ScrollView {
        OnTheRecordView(session: session).padding()
    }
    .background(.night)
    .task {
        if session.state.audit.count < 2 {
            _ = try? await session.editRound(4, hands: PreviewData.sampleRounds[3].hands, knocker: PreviewData.cleoSeat)
            _ = try? await session.extendRounds(by: 2)
        }
    }
    .previewEnvironment()
}
