import SwiftUI

// STUB: owned by table. Replace this file's contents; keep the type name and initializer.
// A minimal working Table so the shell (full-screen cover, minimize, mini bar, toasts) can be
// exercised before the real one lands.

/// The live Table (design §6), presented full screen by `MainTabView`.
struct TableView: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @State private var isRecording = false

    var body: some View {
        let state = session.state
        NavigationStack {
            List {
                Section {
                    ForEach(state.standings) { standing in
                        HStack(spacing: 12) {
                            Text(standing.rank.label).kedroFont(.headline).frame(width: 28)
                            AvatarView(seat: standing.seat, isLeader: standing.isLeader, isDealer: standing.isDealer)
                            Text(standing.seat.displayName).kedroFont(.headline)
                            Spacer()
                            VStack(alignment: .trailing) {
                                ScoreText(value: standing.total)
                                    .foregroundStyle(standing.isLeader ? Color.gold : Color.cream)
                                if let last = standing.lastRound {
                                    Text(Literal.delta(last)).font(.caption).foregroundStyle(.silver)
                                }
                            }
                        }
                    }
                } header: {
                    Text(Literal.roundOf(state.progress.currentRound, state.progress.plannedRounds)).kedroFont(.label)
                }
            }
            .navigationTitle(state.config.tableWord)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Minimize", systemImage: "chevron.down") { app.minimizeTable() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !state.status.isLive {
                        Button("Done") { app.closeLiveGame() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if state.status.isLive {
                    Button(Literal.recordRound(state.nextRoundNumber)) { isRecording = true }
                        .buttonStyle(.kedroPrimary)
                        .padding()
                }
            }
            .sheet(isPresented: $isRecording) {
                RoundSheet(session: session)
            }
            .onChange(of: isRecording) { _, open in app.toasts.isDeferring = open }
        }
        .keepsScreenAwake(state.status.isLive)
    }
}

#Preview {
    TableView(session: PreviewData.sampleSession())
        .previewEnvironment(AppModel.preview(liveGame: true))
}
