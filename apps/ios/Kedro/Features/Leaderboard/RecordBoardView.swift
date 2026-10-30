import SwiftUI

/// A records board: the top 25 for one record (design §12.4), pushed from the records grid.
struct RecordBoardView: View {
    let kind: RecordKind
    let scope: LeaderboardScope

    @Environment(AppModel.self) private var app
    @State private var server = ServerStats.shared

    private var stats: StatsModel { .shared(for: app.store) }
    private var viewer: PlayerRef? { app.profile?.identity }

    /// The server's records when loaded (every game, every claimed guest); this phone's offline.
    private var entries: [RecordEntry] {
        server.records(kind, scope: scope) ?? stats.snapshot.records(kind, scope: scope, viewer: viewer)
    }

    var body: some View {
        let entries = entries
        List {
            Section {
                ForEach(entries) { entry in
                    NavigationLink(value: AppRoute.profile(entry.ref)) {
                        row(entry)
                    }
                    .listRowBackground(entry.ref == viewer ? Color.kedroRed.opacity(0.12) : Color.surface)
                }
            } header: {
                Text("\(scope.label) · top \(RecordBoardView.limit)")
            } footer: {
                Text(kind.definition)
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Record Yet",
                    systemImage: "trophy",
                    description: Text("Finish a game and someone will hold this.")
                )
            }
        }
        .scrollContentBackground(.hidden)
        .background(.night)
        .navigationTitle(kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .task { await stats.follow(app.store, viewer: viewer) }
        .task { await server.loadRecords(scope, api: app.api) }
        .refreshable { await server.loadRecords(scope, api: app.api, force: true) }
    }

    static let limit = 25

    private func row(_ entry: RecordEntry) -> some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .kedroFont(.headline)
                .foregroundStyle(entry.rank == 1 ? .gold : .cream)
                .frame(minWidth: 28, alignment: .leading)
            StatsAvatar(identity: entry.identity, size: .compact)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.identity.name).kedroFont(.headline).foregroundStyle(.cream)
                if let word = entry.tableWord, let date = entry.date {
                    Text("\(word) · \(date.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.caption)
                        .foregroundStyle(.silverDim)
                }
            }
            Spacer()
            Text(ScoreFormat.string(entry.value))
                .kedroFont(.scoreCompact)
                .foregroundStyle(entry.rank == 1 ? .gold : .cream)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.identity.name), rank \(entry.rank), \(kind.label) \(ScoreFormat.spoken(entry.value))")
    }
}

#Preview {
    NavigationStack { RecordBoardView(kind: .mostLandedKnocks, scope: .playedWith) }
        .previewEnvironment()
}
