import SwiftUI

/// Everything the Table presents as a sheet.
enum TableSheet: Identifiable, Hashable {
    case record
    case history(HistoryTab)
    case talk(TauntTarget)
    case rules
    case why(Round)
    case dealer
    case liveKnock
    case handOff
    case extend
    case addPlayer
    case receipt
    case invite

    var id: String {
        switch self {
        case .record: "record"
        case .history: "history"
        case .talk: "talk"
        case .rules: "rules"
        case .why: "why"
        case .dealer: "dealer"
        case .liveKnock: "liveKnock"
        case .handOff: "handOff"
        case .extend: "extend"
        case .addPlayer: "addPlayer"
        case .receipt: "receipt"
        case .invite: "invite"
        }
    }
}

/// A small sheet with a title, an avatar row and a hint: "Who's dealing?", "Who knocked?",
/// "Who keeps score?". One tap picks and closes.
struct SeatChoiceSheet: View {
    let title: String
    var hint: String?
    let seats: [Seat]
    var selected: SeatID?
    var marksKnocker = false
    let onPick: (SeatID) async throws -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .kedroFont(.label)
                .foregroundStyle(.silver)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            SeatPickerRow(seats: seats, selected: selected, marksKnocker: marksKnocker, size: .standings) { seat in
                pick(seat)
            }
            .disabled(isWorking)
            if let hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.silverDim)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(230), .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.surface)
    }

    private func pick(_ seat: SeatID) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await onPick(seat)
                dismiss()
            } catch {
                app.toasts.show(error.localizedDescription)
            }
        }
    }
}

/// "Who's dealing?" (design §6.4): tap the D chip or the metadata line, then a seat. Logged.
struct DealerPickerSheet: View {
    let session: GameSession

    var body: some View {
        let state = session.state
        SeatChoiceSheet(
            title: TableText.text("label.whosDealing"),
            hint: TableText.text("label.dealerHint"),
            seats: state.seats,
            selected: state.currentDealer
        ) { seat in
            guard seat != session.state.currentDealer else { return }
            try await session.changeDealer(to: seat)
        }
    }
}

/// The live knock (design §7.5): "Who knocked?" with you first, so marking yourself is two taps
/// (Knock, you). A second attempt shows "Ana already marked Noah" with Change.
struct LiveKnockSheet: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var isChanging = false

    var body: some View {
        let state = session.state
        if let mark = state.liveKnock, !isChanging {
            VStack(alignment: .leading, spacing: 14) {
                Text(TableText.text("label.alreadyMarked", ["name": mark.markedByName, "knocker": state.name(of: mark.knocker)]))
                    .font(.headline)
                    .foregroundStyle(.cream)
                HStack(spacing: 10) {
                    Button(TableText.text("button.change")) { isChanging = true }
                        .buttonStyle(.kedroGlassWide)
                    Button(TableText.text("button.clearKnock")) {
                        Task {
                            do {
                                try await session.markKnock(nil)
                                dismiss()
                            } catch {
                                app.toasts.show(error.localizedDescription)
                            }
                        }
                    }
                    .buttonStyle(.kedroGlassWide)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .presentationDetents([.height(190)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.surface)
        } else {
            SeatChoiceSheet(
                title: TableText.text("label.whoKnocked"),
                hint: TableText.text("label.liveKnockHint"),
                seats: Self.youFirst(state.seats, me: session.mySeatID),
                selected: isChanging ? state.liveKnock?.knocker : nil,
                marksKnocker: true
            ) { seat in
                try await session.markKnock(seat)
            }
        }
    }

    /// The picker defaults to you: your avatar comes first.
    static func youFirst(_ seats: [Seat], me: SeatID?) -> [Seat] {
        guard let me, let mine = seats.first(where: { $0.id == me }) else { return seats }
        return [mine] + seats.filter { $0.id != me }
    }
}

/// Hand off scorekeeping (⋯ menu): pick who records the rounds from now on. Logged.
struct HandOffSheet: View {
    let session: GameSession

    var body: some View {
        let state = session.state
        SeatChoiceSheet(
            title: TableText.text("label.handOffTitle"),
            hint: TableText.text("label.handOffHint"),
            seats: state.seats.filter { !$0.isGuest || $0.deviceID != nil },
            selected: state.scorekeeper
        ) { seat in
            guard seat != session.state.scorekeeper else { return }
            try await session.handOffScorekeeping(to: seat)
        }
    }
}

/// Extend (⋯ menu, design §9.3): add 1, 2 or 3 rounds. Logged.
struct ExtendSheet: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false

    var body: some View {
        let planned = session.state.config.plannedRounds
        VStack(alignment: .leading, spacing: 12) {
            Text(TableText.text("label.extendTitle"))
                .kedroFont(.label)
                .foregroundStyle(.silver)
                .accessibilityAddTraits(.isHeader)
            ForEach([1, 2, 3], id: \.self) { count in
                Button {
                    extend(by: count)
                } label: {
                    HStack {
                        Text(count == 1 ? TableText.text("button.addRound") : TableText.text("button.addRounds", ["n": count]))
                        Spacer()
                        Text(TableText.text("label.extendBy", ["total": planned + count]))
                            .font(.footnote)
                            .foregroundStyle(.silver)
                    }
                }
                .buttonStyle(.kedroGlassWide)
            }
        }
        .disabled(isWorking)
        .padding(20)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.surface)
    }

    private func extend(by count: Int) {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await session.extendRounds(by: count)
                dismiss()
            } catch {
                app.toasts.show(error.localizedDescription)
            }
        }
    }
}

#Preview("Dealer") {
    Color.night
        .sheet(isPresented: .constant(true)) { DealerPickerSheet(session: PreviewData.sampleSession()) }
        .previewEnvironment()
}

#Preview("Live knock") {
    Color.night
        .sheet(isPresented: .constant(true)) { LiveKnockSheet(session: PreviewData.sampleSession()) }
        .previewEnvironment()
}

#Preview("Already marked") {
    Color.night
        .sheet(isPresented: .constant(true)) { LiveKnockSheet(session: PreviewData.sampleSession(liveKnock: true)) }
        .previewEnvironment()
}

#Preview("Extend") {
    Color.night
        .sheet(isPresented: .constant(true)) { ExtendSheet(session: PreviewData.sampleSession()) }
        .previewEnvironment()
}
