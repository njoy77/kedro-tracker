import SwiftUI

// STUB: owned by lobby. Replace this file's contents; keep the type name and initializer.
// A minimal working Play tab: start a table, reopen the live game, recent games, and (DEBUG)
// demo data and the sample table.

/// The Play tab (design §12.1). Root of the Play tab's stack; don't add a NavigationStack.
struct PlayView: View {
    @Environment(AppModel.self) private var app
    @State private var recent: [GameSummary] = []

    var body: some View {
        List {
            Section {
                if let live = app.liveGame {
                    Button("Back to \(live.state.config.tableWord)") { app.presentTable() }
                } else {
                    Button(Literal.text("button.newTable")) {
                        Task {
                            let config = GameConfig(plannedRounds: app.preferences.lastPlannedRounds, scoringMode: app.preferences.lastScoringMode)
                            if let session = try? await app.createGame(config: config) {
                                app.startLiveGame(session)
                            }
                        }
                    }
                }
            }
            #if DEBUG
            Section("Debug") {
                Button("Start the Sample Table (Round 6 of 8)") {
                    Task { await startSampleTable() }
                }
                Button("Load Demo Data") {
                    Task {
                        _ = try? await DemoDataSeeder.seed(into: app.store)
                        await reload()
                    }
                }
            }
            #endif
            Section("Recent") {
                ForEach(recent) { game in
                    NavigationLink(value: AppRoute.gameHistory(game.id)) {
                        VStack(alignment: .leading) {
                            Text(game.tableWord).kedroFont(.headline)
                            Text("\(game.status.rawValue.capitalized) · \(game.roundsPlayed) rounds · \(game.seats.map(\.displayName).formatted())")
                                .font(.footnote)
                                .foregroundStyle(.silver)
                        }
                    }
                }
            }
        }
        .navigationTitle("Play")
        .background { SuitWatermark(marks: SuitWatermark.play) }
        .task {
            await reload()
            for await _ in app.store.gameUpdates() { await reload() }
        }
    }

    private func reload() async {
        recent = (try? await app.store.games()) ?? []
    }

    #if DEBUG
    private func startSampleTable() async {
        let operations = PreviewData.sampleOperations(throughRound: 5, finished: false, liveKnock: true)
        _ = try? await app.store.append(operations)
        if let session = try? await app.makeSession(for: PreviewData.sampleGameID) {
            app.startLiveGame(session)
        }
    }
    #endif
}

#Preview {
    NavigationStack { PlayView() }
        .previewEnvironment()
}
