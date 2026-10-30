import SwiftUI

/// The live Table (design §6), presented full screen by `MainTabView` (which applies the toast
/// host). Follows the game through its life: waiting for the deal, being played (or shown in
/// display mode), abandoned (restorable for 15 minutes), and game end once it's finished.
struct TableView: View {
    let session: GameSession

    var body: some View {
        Group {
            switch session.state.status {
            case .lobby:
                TableLobbyWaitingView(session: session)
            case .active:
                LiveTableView(session: session)
            case .finished:
                GameEndView(session: session)
            case .abandoned:
                AbandonedTableView(session: session)
            }
        }
        .animation(.smooth(duration: 0.4), value: session.state.status)
    }
}

/// A table that hasn't been dealt yet (the lobby lives in `NewTableView`; this is what a seated
/// phone sees if it opens the Table before the host taps Deal).
private struct TableLobbyWaitingView: View {
    let session: GameSession

    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(session.state.config.tableWord, systemImage: "suit.spade.fill")
            } description: {
                Text(TableText.text("label.lobbyHint"))
            }
            .background(Color.night.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(TableText.text("button.minimize"), systemImage: "chevron.down") { app.minimizeTable() }
                }
            }
        }
    }
}

/// An abandoned game (design §9.3): it won't count; anyone seated can restore it for 15 minutes.
struct AbandonedTableView: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @State private var isRestoring = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            content(now: context.date)
        }
        .background(.nightGradient)
        .preferredColorScheme(.dark)
    }

    private func content(now: Date) -> some View {
        let state = session.state
        let canRestore = session.mySeatID != nil && session.canRestore(now: now)
        return VStack(spacing: 18) {
            Spacer()
            LogoView(width: 180)
            Text(TableText.text("label.abandoned"))
                .kedroFont(.display)
                .foregroundStyle(.cream)
            Text(TableText.text("label.abandonedNote"))
                .font(.callout)
                .foregroundStyle(.silver)
            if canRestore, let abandonedAt = state.abandonedAt {
                let until = abandonedAt.addingTimeInterval(TimeInterval(GameState.restoreWindowMs / 1000))
                Text(TableText.text("label.restoreUntil", ["time": until.formatted(date: .omitted, time: .shortened)]))
                    .font(.footnote)
                    .foregroundStyle(.silverDim)
            }
            Spacer()
            VStack(spacing: 10) {
                if canRestore {
                    Button(Literal.text("button.restoreGame")) { restore() }
                        .buttonStyle(.kedroPrimary)
                        .disabled(isRestoring)
                }
                Button(Literal.text("button.done")) { app.closeLiveGame() }
                    .buttonStyle(.kedroGlassWide)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func restore() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do { try await session.restore() } catch { app.toasts.show(error.localizedDescription) }
        }
    }
}

#Preview("Table") {
    TableView(session: PreviewData.sampleSession())
        .previewEnvironment(AppModel.preview(liveGame: true))
}

#Preview("Finished") {
    TableView(session: PreviewData.sampleSession(throughRound: 8, finished: true))
        .previewEnvironment()
}

#Preview("Abandoned") {
    let session = PreviewData.sampleSession()
    TableView(session: session)
        .task { _ = try? await session.abandon() }
        .previewEnvironment()
}
