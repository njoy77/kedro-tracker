import SwiftUI

/// The Board tab: sortable leaderboard, records, Hall of Shame, Not Yet Ranked (design §12.4).
/// Root of the Board tab's stack; don't add a NavigationStack.
struct LeaderboardView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("kedro.board.scope") private var scope: LeaderboardScope = .playedWith
    @AppStorage("kedro.board.sort") private var sort: LeaderboardSort = .rating
    /// Global opens on "Around me"; Jump to Top shows the whole board.
    @State private var showsWholeGlobalBoard = false
    @State private var isViewerRowVisible = false
    @State private var record: RecordKind?

    @State private var server = ServerStats.shared

    private var stats: StatsModel { .shared(for: app.store) }
    private var viewer: PlayerRef? { app.profile?.identity }
    private var voice: Voice { app.voice }

    /// Both boards are the server's (one source of truth, and the only place that knows which
    /// guests have claimed their history onto accounts); this phone's own history stands in only
    /// while it's offline or has no account.
    private func board(_ snapshot: StatsSnapshot) -> Leaderboard {
        if let remote = server.board(effectiveScope, sort: sort) { return remote }
        return snapshot.leaderboard(scope: effectiveScope, sort: sort, viewer: viewer)
    }

    /// The records follow the boards: the server's when loaded, this phone's history otherwise.
    private func recordLeader(_ kind: RecordKind, snapshot: StatsSnapshot) -> RecordEntry? {
        if let remote = server.records(kind, scope: effectiveScope) { return remote.first }
        return snapshot.records(kind, scope: effectiveScope, viewer: viewer, limit: 1).first
    }

    private var isShowingLocalGlobal: Bool { effectiveScope == .global && server.global[sort] == nil }

    var body: some View {
        let snapshot = stats.snapshot
        let board = board(snapshot)
        ScrollViewReader { proxy in
            List {
                header
                if board.ranked.isEmpty && board.belowMinimum.isEmpty && board.notYetRanked.isEmpty {
                    emptyState
                } else {
                    rankedSection(board, snapshot: snapshot)
                    belowMinimumSection(board)
                }
                recordsSection(snapshot)
                notYetRankedSection(board)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(.night)
            .safeAreaInset(edge: .bottom) { pinnedRow(board, snapshot: snapshot, proxy: proxy) }
        }
        .navigationTitle("Board")
        .toolbar { sortMenu }
        .navigationDestination(item: $record) { kind in
            RecordBoardView(kind: kind, scope: effectiveScope)
        }
        .animation(.smooth, value: sort)
        .animation(.smooth, value: scope)
        .task { await stats.follow(app.store, viewer: viewer) }
        .task(id: GlobalKey(scope: effectiveScope, sort: sort)) {
            await server.load(effectiveScope, api: app.api, sort: sort, viewer: viewer)
        }
        .task(id: effectiveScope) {
            await server.loadRecords(effectiveScope, api: app.api)
        }
        .refreshable {
            async let board: Void = server.load(effectiveScope, api: app.api, sort: sort, viewer: viewer, force: true)
            async let records: Void = server.loadRecords(effectiveScope, api: app.api, force: true)
            _ = await (board, records)
        }
        .onChange(of: scope) { showsWholeGlobalBoard = false }
    }

    /// Played With needs someone to have played with; a phone with no profile shows everyone.
    private var effectiveScope: LeaderboardScope { viewer == nil ? .global : scope }

    private var isAroundMe: Bool { effectiveScope == .global && !showsWholeGlobalBoard }

    // MARK: Header

    private var header: some View {
        Section {
            if viewer != nil {
                Picker("Scope", selection: $scope) {
                    ForEach(LeaderboardScope.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(effectiveScope.label) · \(sort.headerLabel)")
                    .kedroFont(.label)
                    .foregroundStyle(.silver)
                    .accessibilityAddTraits(.isHeader)
                if isShowingLocalGlobal {
                    Text("Offline: people from games on this phone.")
                        .font(.caption)
                        .foregroundStyle(.silverDim)
                }
            }
        }
    }

    private struct GlobalKey: Hashable {
        var scope: LeaderboardScope
        var sort: LeaderboardSort
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(LeaderboardSort.allCases) { option in
                        VStack {
                            Text(option.label)
                            if let caption = option.caption { Text(caption) }
                        }
                        .tag(option)
                    }
                }
            } label: {
                Label("Sort: \(sort.label)", systemImage: "arrow.up.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityLabel("Sort by \(sort.label)")
        }
    }

    // MARK: Ranked

    @ViewBuilder
    private func rankedSection(_ board: Leaderboard, snapshot: StatsSnapshot) -> some View {
        let rows = visibleRows(board)
        let isTrimmed = rows.count < board.ranked.count
        Section {
            if isAroundMe, isTrimmed {
                Button("Jump to Top") { showsWholeGlobalBoard = true }
                    .font(.subheadline.weight(.semibold))
                    .listRowBackground(Color.surface)
            }
            ForEach(rows) { row in
                NavigationLink(value: AppRoute.profile(row.ref)) {
                    LeaderboardRowView(row: row, sort: sort, closeRace: board.closeRace, snapshot: snapshot, voice: voice)
                }
                .listRowBackground(row.isViewer ? Color.kedroRed.opacity(0.12) : Color.surface)
                .id(row.ref)
                .onScrollVisibilityChange(threshold: 0.5) { visible in
                    if row.isViewer { isViewerRowVisible = visible }
                }
            }
        } footer: {
            if isAroundMe, isTrimmed {
                Text("Around you. \(board.ranked.count) ranked in all.")
            }
        }
    }

    /// Global opens on "Around me": the viewer and their neighbours.
    private func visibleRows(_ board: Leaderboard) -> [LeaderboardRow] {
        guard isAroundMe, board.viewerIndex != nil else { return board.ranked }
        return board.aroundViewer(radius: 3)
    }

    @ViewBuilder
    private func belowMinimumSection(_ board: Leaderboard) -> some View {
        if !board.belowMinimum.isEmpty {
            Section {
                ForEach(board.belowMinimum) { row in
                    NavigationLink(value: AppRoute.profile(row.ref)) {
                        BelowMinimumRowView(row: row, sort: sort, voice: voice)
                    }
                    .listRowBackground(row.isViewer ? Color.kedroRed.opacity(0.12) : Color.surface)
                }
            } header: {
                if let games = sort.minimumGames {
                    Text("Under \(games) games")
                } else if let knocks = sort.minimumKnocks {
                    Text("Under \(knocks) knocks")
                }
            }
        }
    }

    /// Your row, pinned at the bottom while it's out of view (design §12.4).
    @ViewBuilder
    private func pinnedRow(_ board: Leaderboard, snapshot: StatsSnapshot, proxy: ScrollViewProxy) -> some View {
        if let row = board.ranked.first(where: \.isViewer), !isViewerRowVisible || !visibleRows(board).contains(row) {
            Button {
                showsWholeGlobalBoard = true
                withAnimation { proxy.scrollTo(row.ref, anchor: .center) }
            } label: {
                LeaderboardRowView(row: row, sort: sort, closeRace: board.closeRace, snapshot: snapshot, voice: voice)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.surfaceRaised, in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.kedroRed.opacity(0.5)) }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityHint("Scrolls to your row")
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Records and Hall of Shame

    private func recordsSection(_ snapshot: StatsSnapshot) -> some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(RecordKind.allCases) { kind in
                    Button {
                        record = kind
                    } label: {
                        RecordTile(kind: kind, leader: recordLeader(kind, snapshot: snapshot))
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            NavigationLink(value: AppRoute.hallOfShame) {
                HStack(spacing: 12) {
                    KMark(height: 24, style: .tinted(.silver))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hall of Shame").font(.headline).foregroundStyle(.cream)
                        Text("The worst moments among your people.")
                            .font(.footnote)
                            .foregroundStyle(.silver)
                    }
                }
            }
            .listRowBackground(Color.surface)
        } header: {
            Text("Records")
        }
    }

    // MARK: Not Yet Ranked

    @ViewBuilder
    private func notYetRankedSection(_ board: Leaderboard) -> some View {
        if !board.notYetRanked.isEmpty {
            Section {
                if effectiveScope == .global {
                    Text(voice.line("L-03", ["n": board.notYetRanked.count]))
                        .font(.footnote)
                        .foregroundStyle(.silver)
                        .listRowBackground(Color.surface)
                }
                ForEach(board.notYetRanked) { row in
                    NavigationLink(value: AppRoute.profile(row.ref)) {
                        UnrankedRowView(row: row, voice: voice)
                    }
                    .listRowBackground(row.isViewer ? Color.kedroRed.opacity(0.12) : Color.surface)
                }
            } header: {
                Text(voice.line("L-02"))
            }
        }
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView(
                "Nobody on the Board Yet",
                systemImage: "list.number",
                description: Text("Finish a game and the board starts here.")
            )
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Rows

/// One ranked row: the rank for this sort, avatar, name and title, the sort's value.
struct LeaderboardRowView: View {
    let row: LeaderboardRow
    let sort: LeaderboardSort
    let closeRace: CloseRace?
    let snapshot: StatsSnapshot
    let voice: Voice

    var body: some View {
        HStack(spacing: 12) {
            Text(row.rank?.label ?? "")
                .kedroFont(.headline)
                .foregroundStyle(rankColor)
                .frame(minWidth: 30, alignment: .leading)
            StatsAvatar(identity: row.identity, size: .compact, isLeader: isTop && sort == .rating)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.identity.name)
                        .kedroFont(.headline)
                        .foregroundStyle(.cream)
                    if row.isViewer {
                        Text(viewerCaption).font(.caption).foregroundStyle(.silver)
                    } else if row.isNew {
                        Text("new").font(.caption.weight(.semibold)).foregroundStyle(.kedroRed)
                    }
                }
                if let title = snapshot.displayTitle(for: row.ref, chosen: row.identity.titleID) {
                    TitleLabel(title: title, voice: voice)
                }
                if row.isViewer, let viewerLine {
                    Text(viewerLine)
                        .font(.caption)
                        .foregroundStyle(.silver)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(row.valueText)
                .kedroFont(.scoreCompact)
                .foregroundStyle(isTop ? .gold : .cream)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var isTop: Bool { row.rank?.position == 1 }

    private var rankColor: Color {
        if isTop { return .gold }
        return row.isViewer ? .kedroRed : .cream
    }

    private var viewerCaption: String {
        guard sort == .rating, let delta = row.lastRatingDelta else { return "you" }
        return "you · \(ScoreFormat.signed(delta))"
    }

    /// L-06 at #1 by rating, otherwise the close race (L-04).
    private var viewerLine: String? {
        if sort == .rating, isTop { return voice.line("L-06") }
        guard let closeRace else { return nil }
        return voice.line("L-04", ["name": closeRace.name, "gap": closeRace.gapText])
    }

    private var accessibilityText: String {
        var parts = [row.isViewer ? "\(row.identity.name), you" : row.identity.name]
        if let rank = row.rank { parts.append("rank \(rank.position)\(rank.isShared ? ", shared" : "")") }
        parts.append("\(sort.label) \(row.valueText)")
        if row.isViewer, let viewerLine { parts.append(viewerLine) }
        return parts.joined(separator: ", ")
    }
}

/// Eligible but under the sort's minimum: listed without a number (L-05).
private struct BelowMinimumRowView: View {
    let row: LeaderboardRow
    let sort: LeaderboardSort
    let voice: Voice

    var body: some View {
        HStack(spacing: 12) {
            Text("–")
                .kedroFont(.headline)
                .foregroundStyle(.silverDim)
                .frame(minWidth: 30, alignment: .leading)
                .accessibilityHidden(true)
            StatsAvatar(identity: row.identity, size: .compact)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.identity.name).kedroFont(.headline).foregroundStyle(.cream)
                Text(minimumLine).font(.caption).foregroundStyle(.silverDim)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var minimumLine: String {
        if let games = sort.minimumGames { return voice.line("L-05", ["n": games]) }
        if let knocks = sort.minimumKnocks { return voice.line(StatsLiteral.needsKnocks, ["n": knocks]) }
        return ""
    }
}

/// Still in their first ten: the progress meter, no number (L-02).
private struct UnrankedRowView: View {
    let row: UnrankedRow
    let voice: Voice

    var body: some View {
        HStack(spacing: 12) {
            StatsAvatar(identity: row.identity, size: .compact)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.identity.name).font(.body).foregroundStyle(.cream)
                if row.isViewer {
                    Text(voice.line("L-01", ["n": row.gamesPlayed, "left": row.gamesLeft]))
                        .font(.caption)
                        .foregroundStyle(.silver)
                }
            }
            Spacer()
            ProgressMeter(value: row.gamesPlayed)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A records grid tile: label and the current holder.
private struct RecordTile: View {
    let kind: RecordKind
    let leader: RecordEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kind.label).kedroFont(.label).foregroundStyle(.silver)
            if let leader {
                Text("\(Text(leader.identity.name).fontWeight(.semibold)) · \(ScoreFormat.string(leader.value))")
                    .font(.subheadline)
                    .foregroundStyle(.cream)
                    .lineLimit(1)
            } else {
                Text("Nobody yet").font(.subheadline).foregroundStyle(.silverDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.surface, in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the top 25")
    }
}

#Preview("Board") {
    NavigationStack { LeaderboardView().appRouteDestinations() }
        .previewEnvironment()
}

#Preview("Board, empty") {
    NavigationStack { LeaderboardView() }
        .previewEnvironment(AppModel.preview(seeded: false))
}
