import SwiftUI

/// History (design §9.1, mockup frame 11): Scores (rounds × players), On the record (every edit)
/// and Feed. Tap any score to fix it (four taps, §9.2) until the game finishes.
///
/// Doesn't create a `NavigationStack`: the Table wraps it in one for the sheet, and
/// `GameRecordView` pushes it on a tab's stack for finished games.
struct HistorySheet: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @State private var tab: HistoryTab
    @State private var fixing: ScoreCellRef?

    init(session: GameSession) {
        self.init(session: session, initialTab: .scores)
    }

    init(session: GameSession, initialTab: HistoryTab) {
        self.session = session
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        let state = session.state
        VStack(spacing: 12) {
            Picker(TableText.text("button.history"), selection: $tab) {
                ForEach(HistoryTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            switch tab {
            case .scores:
                scores(state)
            case .record:
                ScrollView {
                    OnTheRecordView(session: session)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            case .feed:
                FeedView(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.night.ignoresSafeArea())
        .sheet(item: $fixing) { cell in
            CorrectionSheet(session: session, roundNumber: cell.round, focus: cell.seat)
        }
    }

    private var canEdit: Bool { session.canEdit && session.state.status == .active }

    @ViewBuilder
    private func scores(_ state: GameState) -> some View {
        let voice = app.houseVoice(for: state)
        VStack(spacing: 8) {
            if state.status == .finished {
                Text(voice.line("H-04"))
                    .font(.footnote)
                    .foregroundStyle(.silver)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.surface, in: .rect(cornerRadius: 12))
                    .padding(.horizontal, 16)
            }
            if !state.conflicts.isEmpty {
                Button {
                    tab = .record
                } label: {
                    Label(voice.line("H-06", ["r": state.conflicts[0].roundNumber]), systemImage: "exclamationmark.bubble")
                        .font(.footnote)
                        .foregroundStyle(.cream)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.surfaceRaised, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
            if state.rounds.isEmpty {
                ContentUnavailableView(Literal.recordRound(1), systemImage: "suit.spade")
            } else if dynamicTypeIsAccessibility {
                ScrollView {
                    ScoresGrid(state: state, canEdit: canEdit) { fixing = $0 }
                        .padding(.horizontal, 16)
                }
            } else {
                // Short games hug their rows; long ones scroll inside the card with totals pinned.
                ViewThatFits(in: .vertical) {
                    ScoresGrid(state: state, canEdit: canEdit) { fixing = $0 }
                        .fixedSize(horizontal: false, vertical: true)
                    ScoresGrid(state: state, canEdit: canEdit) { fixing = $0 }
                }
                .padding(.horizontal, 16)
            }
            if canEdit, !state.rounds.isEmpty {
                Text(voice.line("H-07"))
                    .font(.caption)
                    .foregroundStyle(.silverDim)
            }
            Spacer(minLength: 0)
        }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var dynamicTypeIsAccessibility: Bool { dynamicTypeSize.isAccessibilitySize }
}

#Preview("Live") {
    NavigationStack {
        HistorySheet(session: PreviewData.sampleSession(throughRound: 5))
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
    }
    .previewEnvironment()
}

#Preview("Finished, On the record") {
    NavigationStack {
        HistorySheet(session: PreviewData.sampleSession(throughRound: 8, finished: true), initialTab: .record)
    }
    .previewEnvironment()
}

#Preview("8 players") {
    NavigationStack {
        HistorySheet(session: TablePreviews.eightPlayerSession)
    }
    .previewEnvironment()
}
