import SwiftUI

/// The minimized Table in the tab bar accessory: "COLD DECK · R6/8 · You 1st · 26".
/// Tapping it brings the Table back.
struct LiveGameMiniBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let session = app.liveGame {
            Button {
                app.presentTable()
            } label: {
                content(session.state, mySeat: session.mySeatID)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the table")
        }
    }

    private func content(_ state: GameState, mySeat: SeatID?) -> some View {
        HStack(spacing: 8) {
            KMark(height: 18)
            Text(summary(state, mySeat: mySeat))
                .kedroFont(.label)
                .foregroundStyle(.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.silver)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
    }

    private func summary(_ state: GameState, mySeat: SeatID?) -> String {
        let word = state.config.tableWord
        if state.status == .lobby {
            return "\(word.uppercased()) · Lobby · \(state.seats.count) seated"
        }
        let progress = state.progress
        if let mySeat, let standing = state.standing(for: mySeat) {
            return Literal.miniBar(word: word, round: progress.currentRound, total: progress.plannedRounds, rank: standing.rank, score: standing.total)
        }
        return "\(word.uppercased()) · R\(progress.currentRound)/\(progress.plannedRounds)"
    }
}

#Preview {
    LiveGameMiniBar()
        .frame(height: 48)
        .background(.surface)
        .previewEnvironment(AppModel.preview(liveGame: true))
}
