import SwiftUI

/// The Play tab (design §12.1, mockup frame 4). Top to bottom: the Table card if one's nearby
/// (it rises over everything, §5.3); Since you last looked; Tonight's stakes; New Table with Join
/// with Code beside it; the Wrapped card in December; Learn Cambio (first 3 games); Nearby rows
/// for dismissed tables; Recent games with Run It Back.
///
/// Root of the Play tab's stack; doesn't create a NavigationStack.
struct PlayView: View {
    @Environment(AppModel.self) private var app
    @State private var model: PlayModel?

    var body: some View {
        Group {
            if let model {
                PlayScreen(model: model)
            } else {
                Color.clear
            }
        }
        .navigationTitle("Play")
        .task {
            if model == nil { model = PlayModel(app: app) }
        }
    }
}

private struct PlayScreen: View {
    let model: PlayModel

    @Environment(AppModel.self) private var app
    @Environment(NetworkServices.self) private var network: NetworkServices?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lobby: LobbyStart?
    @State private var isJoiningWithCode = false
    @State private var isShowingOtherTables = false
    @State private var isEndingGame = false

    private var me: PlayerRef? { app.profile?.identity }

    /// "Is this Sam?" (design §5.7).
    private var guestSeatQuestion: String {
        "Is this \(model.guestSeatConfirmation?.seat.displayName ?? "you")?"
    }

    var body: some View {
        List {
            liveGameSection
            digestSection
            stakesSection
            startSection
            wrappedSection
            nearbySection
            learnSection
            recentSection
            #if DEBUG
            debugSection
            #endif
        }
        .scrollContentBackground(.hidden)
        .background { SuitWatermark(marks: SuitWatermark.play) }
        .background(.night)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: AppRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Leaves room so the last rows can scroll out from under the card.
            if model.card != nil { Color.clear.frame(height: 24) }
        }
        .overlay(alignment: .bottom) { tableCard }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15), value: model.card?.id)
        .newTableSheet($lobby)
        .sheet(isPresented: $isJoiningWithCode) { JoinWithCodeSheet(model: model) }
        .confirmationDialog(
            guestSeatQuestion,
            isPresented: Binding(get: { model.guestSeatConfirmation != nil }, set: { if !$0 { model.guestSeatConfirmation = nil } }),
            titleVisibility: .visible,
            presenting: model.guestSeatConfirmation
        ) { _ in
            Button(Literal.text("button.thatsMe")) { Task { await model.confirmGuestSeat() } }
            Button("Not Me") { Task { await model.declineGuestSeat() } }
        } message: { confirmation in
            Text("\(confirmation.seat.displayName) has a seat at this table with no phone. Your phone takes it over.")
        }
        .sheet(isPresented: $isShowingOtherTables) {
            OtherTablesSheet(tables: model.otherTables) { table in
                model.showCard(for: table)
                isShowingOtherTables = false
            }
        }
        .task { await model.followStore() }
        .task { await model.followNearbyTables() }
        .onChange(of: app.liveGame?.state.seats.map(\.id)) { model.checkAskAnswered() }
        .onOpenURL { url in
            Task {
                if await model.open(url) { app.selectedTab = .play }
            }
        }
        // Run It Back from game end: open the lobby once the Table's cover has gone.
        .task(id: app.rematchRequest?.gameID) {
            guard let previous = app.rematchRequest else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            app.rematchRequest = nil
            lobby = .rematch(previous)
        }
        // A tapped push (N-01 saved seat, N-07 nearby) or a table link the app was opened with.
        .onChange(of: network?.push.pendingInvite, initial: true) { _, invite in
            guard let invite else { return }
            network?.push.consumeInvite()
            Task {
                if await model.open(Self.link(for: invite).url) { app.selectedTab = .play }
            }
        }
        // Stats reload off the main actor; refresh the digest, stakes and Wrapped when they land.
        .onChange(of: StatsKey(stats: StatsModel.shared(for: app.store))) { model.refreshInsights() }
        .onDisappear { model.markLooked() }
    }

    private struct StatsKey: Equatable {
        var isLoaded: Bool
        var games: Int

        init(stats: StatsModel) {
            isLoaded = stats.isLoaded
            games = stats.snapshot.games.count
        }
    }

    private static func link(for invite: TableInvite) -> TableInviteLink {
        TableInviteLink(
            kind: invite.source == .link ? .table : .savedSeat,
            gameID: invite.gameID,
            token: invite.inviteCode,
            hostName: invite.hostName,
            tableWord: invite.tableWord
        )
    }

    // MARK: The Table card

    @ViewBuilder
    private var tableCard: some View {
        if let card = model.card {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { model.dismissCard() }
                    .accessibilityHidden(true)
                TableCardView(
                    content: card,
                    stakes: model.stakes(at: card),
                    myGamesPlayed: model.myGamesPlayed,
                    otherTablesCount: model.otherTables.count,
                    isWaitingForHost: model.askedTable == card.id,
                    isWorking: model.isJoining,
                    onAction: { Task { await model.performCardAction() } },
                    onShowOthers: { isShowingOtherTables = true },
                    onDismiss: { model.dismissCard() }
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Live game

    @ViewBuilder
    private var liveGameSection: some View {
        if let live = app.liveGame, live.state.status.isLive {
            Section {
                let isMyLobby = live.state.status == .lobby && live.state.hostSeat != nil && live.state.hostSeat == live.mySeatID
                Button {
                    if isMyLobby { lobby = .resume(live) } else { app.presentTable() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "suit.spade.fill").foregroundStyle(.kedroRed)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isMyLobby ? "Back to Your Table" : "Back to \(live.state.config.tableWord)")
                                .foregroundStyle(.cream)
                            Text(live.state.status == .lobby ? "Waiting to deal" : Literal.roundOf(live.state.progress.currentRound, live.state.progress.plannedRounds).capitalized)
                                .font(.footnote)
                                .foregroundStyle(.silver)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.silverDim)
                    }
                    .frame(minHeight: 44)
                }
                // End it from here without opening the Table (design §9.3).
                .swipeActions(edge: .trailing) {
                    if live.canEdit {
                        Button(Literal.text("button.endGame"), systemImage: "flag.checkered") { isEndingGame = true }
                            .tint(.kedroRed)
                    }
                }
                .contextMenu {
                    if live.canEdit {
                        Button(Literal.text("button.endGame"), systemImage: "flag.checkered") { isEndingGame = true }
                    }
                }
                .endGameDialog(live, isPresented: $isEndingGame)
            }
        }
    }

    // MARK: Since you last looked

    @ViewBuilder
    private var digestSection: some View {
        if !model.digest.isEmpty {
            Section("Since you last looked") {
                ForEach(model.digest) { item in
                    digestRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func digestRow(_ item: DigestItem) -> some View {
        switch item {
        case .stats(let line):
            statsDigestRow(line)
        case let .lastGame(gameID, word, rank, isWin):
            NavigationLink(value: AppRoute.gameHistory(gameID)) {
                HStack(spacing: 12) {
                    Text(rank.ordinal.uppercased())
                        .kedroFont(.label)
                        .foregroundStyle(isWin ? Color.night : .cream)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isWin ? Color.gold : .surfaceRaised, in: .capsule)
                    // TODO(stats): J-09 adds "Rating {delta}" once Core/Stats exposes rating changes.
                    Text(isWin ? "Won at \(word)." : "\(rank.ordinal) at \(word).")
                        .font(.subheadline)
                        .foregroundStyle(.cream)
                }
            }
        case .rivalryFlipped(let rivalry):
            NavigationLink(value: me.map { AppRoute.headToHead($0, rivalry.opponent) } ?? AppRoute.profile(rivalry.opponent)) {
                HStack(spacing: 12) {
                    AvatarView(avatar: rivalry.avatar, name: rivalry.name, isGuest: rivalry.isGuest, size: .compact)
                    Text(app.voice.line("J-08", ["name": rivalry.name, "a": rivalry.mine, "b": rivalry.theirs]))
                        .font(.subheadline)
                        .foregroundStyle(.cream)
                }
            }
        case let .receipt(_, gameID, fromName, fromAvatar, fromIsGuest, word):
            NavigationLink(value: AppRoute.gameHistory(gameID)) {
                HStack(spacing: 12) {
                    AvatarView(avatar: fromAvatar, name: fromName, isGuest: fromIsGuest, size: .compact)
                    Text(app.voice.line("N-08", ["name": fromName, "word": word]))
                        .font(.subheadline)
                        .foregroundStyle(.cream)
                }
            }
        }
    }

    /// A Core/Stats line, linked to where it happened.
    @ViewBuilder
    private func statsDigestRow(_ item: SinceYouLastLookedItem) -> some View {
        let text = Text(item.text).font(.subheadline).foregroundStyle(.cream)
        switch item.kind {
        case .lastGame(let game):
            NavigationLink(value: AppRoute.gameHistory(game)) { text }
        case .passed(let person), .rivalryFlipped(let person), .titleLost(_, by: let person):
            NavigationLink(value: me.map { AppRoute.headToHead($0, person) } ?? AppRoute.profile(person)) { text }
        case .hallOfShame:
            NavigationLink(value: AppRoute.hallOfShame) { text }
        case .closestBadge:
            if let me {
                NavigationLink(value: AppRoute.badges(me)) { text }
            } else {
                text
            }
        }
    }

    // MARK: Stakes

    private var stakesSection: some View {
        Section("Tonight's stakes") {
            ForEach(model.stakes, id: \.self) { line in
                Text(line.text(app.voice))
                    .font(.subheadline)
                    .foregroundStyle(.cream)
            }
        }
    }

    // MARK: New Table / Join with Code

    private var startSection: some View {
        Section {
            HStack(spacing: 10) {
                Button(Literal.text("button.newTable")) { lobby = .fresh }
                    .buttonStyle(.kedroPrimary)
                    .disabled(app.liveGame?.state.status.isLive == true)
                Button(Literal.text("button.joinWithCode")) { isJoiningWithCode = true }
                    .buttonStyle(.kedroGlassWide)
                    .frame(maxWidth: 170)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
        } footer: {
            if app.liveGame?.state.status.isLive == true {
                Text("Finish or leave your current table to start another.")
            }
        }
    }

    // MARK: Wrapped (December)

    @ViewBuilder
    private var wrappedSection: some View {
        if let slot = model.wrapped {
            Section {
                NavigationLink(value: AppRoute.wrapped(year: slot.year)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kedro Wrapped \(String(slot.year))")
                            .kedroFont(.headline)
                            .foregroundStyle(.gold)
                        Text(slot.text)
                            .font(.subheadline)
                            .foregroundStyle(.cream)
                    }
                    .padding(.vertical, 4)
                }
            }
        } else if !StatsModel.shared(for: app.store).isLoaded {
            fallbackWrappedSection
        }
    }

    /// Before stats have loaded: the December card from finished games.
    @ViewBuilder
    private var fallbackWrappedSection: some View {
        let calendar = Calendar.current
        let now = Date.now
        if calendar.component(.month, from: now) == 12 {
            let year = calendar.component(.year, from: now)
            let gamesThisYear = model.finished.filter { game in
                guard let me, game.seat(for: me) != nil, let finished = game.finishedAt else { return false }
                return calendar.component(.year, from: finished) == year
            }.count
            Section {
                NavigationLink(value: AppRoute.wrapped(year: year)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kedro Wrapped \(String(year))")
                            .kedroFont(.headline)
                            .foregroundStyle(.gold)
                        Text(gamesThisYear >= 10
                             ? app.voice.line("N-09", ["year": String(year)])
                             : app.voice.line("WR-23", ["left": 10 - gamesThisYear]))
                            .font(.subheadline)
                            .foregroundStyle(.cream)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: Nearby

    @ViewBuilder
    private var nearbySection: some View {
        if !model.nearbyRows.isEmpty {
            Section("Nearby") {
                ForEach(model.nearbyRows) { table in
                    HStack(spacing: 12) {
                        AvatarView(player: table.host, size: .compact)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(table.host.displayName)'s Table").foregroundStyle(.cream)
                            Text(table.tableWord.uppercased()).kedroFont(.label).foregroundStyle(.silver)
                        }
                        Spacer()
                        Button(table.seatsAreLocked ? Literal.text("button.watch") : (table.isPlayedWith ? Literal.text("button.sitDown") : Literal.text("button.askToSit"))) {
                            model.showCard(for: table)
                            Task { await model.performCardAction() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.kedroRed)
                        .disabled(model.isJoining)
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }

    // MARK: Learn

    @ViewBuilder
    private var learnSection: some View {
        if model.myGamesPlayed < 3 {
            Section {
                NavigationLink(value: AppRoute.learn) {
                    HStack(spacing: 12) {
                        Image(systemName: "graduationcap").foregroundStyle(.kedroRed)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Learn Cambio").foregroundStyle(.cream)
                            Text("Two minutes, then a knock quiz.").font(.footnote).foregroundStyle(.silver)
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }

    // MARK: Recent

    @ViewBuilder
    private var recentSection: some View {
        if !model.recent.isEmpty {
            Section("Recent") {
                ForEach(model.recent.prefix(20)) { game in
                    NavigationLink(value: AppRoute.gameHistory(game.id)) {
                        RecentGameRow(game: game, me: me)
                    }
                    .swipeActions(edge: .trailing) {
                        if game.status == .finished {
                            Button(Literal.text("button.runItBack"), systemImage: "arrow.trianglehead.counterclockwise") {
                                runItBack(game.id)
                            }
                            .tint(.kedroRed)
                        }
                    }
                    .contextMenu {
                        if game.status == .finished {
                            Button(Literal.text("button.runItBack"), systemImage: "arrow.trianglehead.counterclockwise") {
                                runItBack(game.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private func runItBack(_ id: GameID) {
        Task {
            guard app.liveGame?.state.status.isLive != true,
                  let state = try? await app.store.gameState(id) else { return }
            lobby = .rematch(state)
        }
    }

    // MARK: Debug

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            Button("Start the Sample Table (Round 6 of 8)") {
                Task {
                    let operations = PreviewData.sampleOperations(throughRound: 5, finished: false, liveKnock: true)
                    _ = try? await app.store.append(operations)
                    if let session = try? await app.makeSession(for: PreviewData.sampleGameID) {
                        app.startLiveGame(session)
                    }
                }
            }
            Button("Load Demo Data") {
                Task { _ = try? await DemoDataSeeder.seed(into: app.store) }
            }
        }
    }
    #endif
}

/// A game in Recent: table word, when, your finish and score, how many played.
private struct RecentGameRow: View {
    let game: GameSummary
    let me: PlayerRef?

    private var mine: Standing? {
        guard let me else { return nil }
        return game.standings.first { $0.seat.player == me }
    }

    private var detail: String {
        var parts: [String] = []
        switch game.status {
        case .abandoned: parts.append("Abandoned")
        case .lobby: parts.append("Not dealt")
        case .active: parts.append("Round \(game.roundsPlayed + 1) of \(game.plannedRounds)")
        case .finished:
            if let mine { parts.append(mine.isLeader ? "You won · \(ScoreFormat.string(mine.total))" : "You \(mine.rank.ordinal) · \(ScoreFormat.string(mine.total))") }
        }
        parts.append("\(game.seats.count) players")
        if let date = game.finishedAt ?? game.updatedAt {
            parts.append(date.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(game.tableWord.uppercased())
                    .kedroFont(.headline)
                    .foregroundStyle(game.status == .abandoned ? Color.silverDim : .cream)
                Text(detail).font(.footnote).foregroundStyle(.silver)
            }
            Spacer()
            HStack(spacing: -8) {
                ForEach(game.seats.prefix(4)) { seat in
                    AvatarView(seat: seat, size: .compact)
                        .overlay { Circle().stroke(.surface, lineWidth: 2) }
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// "2 other tables nearby": the list with table words (design §5.3).
private struct OtherTablesSheet: View {
    let tables: [NearbyTable]
    var onPick: (NearbyTable) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(tables) { table in
                    Button { onPick(table) } label: {
                        HStack(spacing: 12) {
                            AvatarView(player: table.host, size: .compact)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(table.host.displayName)'s Table").foregroundStyle(.cream)
                                Text(table.tableWord.uppercased()).kedroFont(.label).foregroundStyle(.silver)
                            }
                            Spacer()
                            Text("\(table.seatedPlayers.count + table.guestCount) seated")
                                .font(.footnote)
                                .foregroundStyle(.silverDim)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle("Tables Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Literal.text("button.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Play") {
    NavigationStack { PlayView() }
        .previewEnvironment()
}

#Preview("Play, mid-game") {
    NavigationStack { PlayView() }
        .previewEnvironment(AppModel.preview(liveGame: true))
}
