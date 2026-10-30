import SwiftUI

/// End Game (design §9.3): one confirmation, from the Table or the Play screen, that says
/// up front whether the game will count. 3+ rounds count; fewer stay in history but don't count
/// for stats or the leaderboard (G-07); with no rounds there's nothing to keep, so ending it
/// abandons it (G-08). Abandon is offered too and gets its own confirmation (G-04).
struct EndGameDialog: ViewModifier {
    let session: GameSession
    @Binding var isPresented: Bool

    @Environment(AppModel.self) private var app
    @State private var isConfirmingAbandon = false

    private var state: GameState { session.state }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(Literal.text("button.endGame"), isPresented: $isPresented, titleVisibility: .visible) {
                if state.rounds.isEmpty {
                    Button(Literal.text("button.endGame"), role: .destructive) { run { try await session.abandon() } }
                } else {
                    if state.progress.isComplete {
                        Button(Literal.text("button.finishGame")) { run { try await session.finish(reason: .completed) } }
                    } else {
                        Button(Literal.text("button.endGame")) { run { try await session.finish(reason: .endedEarly) } }
                    }
                    Button(Literal.text("button.abandon"), role: .destructive) { isConfirmingAbandon = true }
                }
                Button(TableText.text("button.cancel"), role: .cancel) {}
            } message: {
                Text(message)
            }
            .alert(Literal.text("button.abandon"), isPresented: $isConfirmingAbandon) {
                Button(Literal.text("button.abandon"), role: .destructive) { run { try await session.abandon() } }
                Button(TableText.text("button.cancel"), role: .cancel) {}
            } message: {
                Text(app.houseVoice(for: state).line("G-04"))
            }
    }

    private var message: String {
        let voice = app.houseVoice(for: state)
        let played = state.rounds.count
        if played == 0 { return voice.line("G-08") }
        if played < GameConfig.countedMinimumRounds { return voice.line("G-07", ["r": played]) }
        return voice.line("G-03", ["r": played])
    }

    private func run(_ work: @escaping () async throws -> Void) {
        let toasts = app.toasts
        Task {
            do { try await work() } catch { toasts.show(error.localizedDescription) }
        }
    }
}

extension View {
    /// Presents End Game for a live game (see `EndGameDialog`).
    func endGameDialog(_ session: GameSession, isPresented: Binding<Bool>) -> some View {
        modifier(EndGameDialog(session: session, isPresented: isPresented))
    }
}

#Preview {
    @Previewable @State var isPresented = true
    let app = AppModel.preview(liveGame: true)
    return Group {
        if let session = app.liveGame {
            Button("End Game") { isPresented = true }
                .endGameDialog(session, isPresented: $isPresented)
        }
    }
    .previewEnvironment(app)
}
