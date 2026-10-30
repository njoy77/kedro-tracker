import SwiftUI

/// A player's profile, also the You tab (design §12.2). Profiles are public: other people see the
/// same view with Play Again and Send a Receipt.
struct ProfileView: View {
    let player: PlayerRef

    @Environment(AppModel.self) private var app
    @State private var isPickingTitle = false
    @State private var receiptGame: ReceiptTarget?
    @State private var playAgainFailed = false
    @State private var blockRequest: BlockRequest?
    @State private var server = ServerStats.shared

    private var stats: StatsModel { .shared(for: app.store) }
    private var voice: Voice { app.voice }
    private var me: PlayerRef? { app.profile?.identity }
    private var isMe: Bool { me.map { stats.snapshot.options.canonical($0) == stats.snapshot.options.canonical(player) } ?? false }

    var body: some View {
        let snapshot = stats.snapshot
        let identity = identity(in: snapshot)
        Group {
            if let record = snapshot.record(player) {
                content(record: record, identity: identity, snapshot: snapshot)
            } else if let remote = server.profile(player), let remoteStats = remote.stats {
                // Someone this phone has never finished a game with (opened from Search): their
                // record from the server.
                ScrollView {
                    VStack(spacing: 24) {
                        header(identity: identity, snapshot: snapshot, record: nil)
                        if !isMe { actions(identity: identity, snapshot: snapshot) }
                        lifetime(remoteStats)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            } else if stats.isLoaded {
                ScrollView {
                    header(identity: identity, snapshot: snapshot, record: nil)
                    ContentUnavailableView(
                        "No Games Yet",
                        systemImage: "suit.spade",
                        description: Text(isMe ? "Finish a game and your record starts here." : "Nothing finished on this phone yet.")
                    )
                }
            } else {
                ProgressView()
            }
        }
        .background(.night)
        .navigationTitle(isMe ? "You" : identity.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMe {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: AppRoute.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            } else {
                // Mute Their Taunts (always, from a profile) and Block (design §8.3).
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("More", systemImage: "ellipsis") {
                        ModerationMenu(person: player, name: identity.name) { blockRequest = $0 }
                    }
                }
            }
        }
        .blockConfirmation($blockRequest)
        .sheet(isPresented: $isPickingTitle) {
            TitlePickerSheet(player: player)
        }
        .sheet(item: $receiptGame) { target in
            ReceiptComposer(gameID: target.id)
                .toastHost(app.toasts)
        }
        .alert("Couldn't Open a Table", isPresented: $playAgainFailed) {
            Button(Literal.text("button.done"), role: .cancel) {}
        } message: {
            Text("Make sure you have a profile, then try again.")
        }
        .task { await stats.follow(app.store, viewer: me) }
        .task(id: player) { await server.loadProfile(api: app.api, player: player) }
        .refreshable { await server.loadProfile(api: app.api, player: player, force: true) }
    }

    private func identity(in snapshot: StatsSnapshot) -> StatsParticipant {
        if let known = snapshot.identity(of: player) {
            if isMe, let profile = app.profile {
                var mine = known
                mine.name = profile.displayName
                mine.avatar = profile.avatar ?? known.avatar
                mine.titleID = profile.titleID
                return mine
            }
            return known
        }
        if isMe, let profile = app.profile {
            return StatsParticipant(ref: profile.identity, seatedAs: profile.identity, name: profile.displayName, avatar: profile.avatar, handle: profile.handle, titleID: profile.titleID)
        }
        if let remote = server.profile(player)?.player {
            return StatsParticipant(ref: player, seatedAs: player, name: remote.displayName, avatar: remote.avatar, handle: remote.handle, titleID: remote.titleID)
        }
        return StatsParticipant(ref: player, seatedAs: player, name: "Someone")
    }

    // MARK: Content

    private func content(record: PlayerRecord, identity: StatsParticipant, snapshot: StatsSnapshot) -> some View {
        let playerStats = PlayerStats(record: record, excluded: snapshot.options.excluded)
        return ScrollView {
            VStack(spacing: 24) {
                header(identity: identity, snapshot: snapshot, record: record)
                if !isMe { actions(identity: identity, snapshot: snapshot) }
                atAGlance(playerStats)
                streaks(playerStats)
                knocking(playerStats)
                games(playerStats)
                rivalry(playerStats, snapshot: snapshot)
                badges(record)
                shame(snapshot)
                if isMe { wrapped(snapshot) }
                history(record)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(alignment: .topTrailing) { SuitWatermark(marks: SuitWatermark.play) }
    }

    // MARK: Header

    private func header(identity: StatsParticipant, snapshot: StatsSnapshot, record: PlayerRecord?) -> some View {
        VStack(spacing: 8) {
            StatsAvatar(identity: identity, ref: player, size: .profile)
            Text(identity.name)
                .kedroFont(.display)
                .foregroundStyle(.cream)
                .accessibilityAddTraits(.isHeader)
            titleLine(identity: identity, snapshot: snapshot)
            if record == nil, let remote = server.profile(player) {
                serverRankLine(remote)
            }
            if let record {
                rankLine(record: record, snapshot: snapshot)
                if !record.isRanked {
                    ProgressMeter(value: record.gamesPlayed)
                    if isMe {
                        Text(voice.line("L-01", ["n": record.gamesPlayed, "left": Ratings.rankedAfterGames - record.gamesPlayed]))
                            .font(.footnote)
                            .foregroundStyle(.silver)
                            .multilineTextAlignment(.center)
                    }
                }
                form(record)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func titleLine(identity: StatsParticipant, snapshot: StatsSnapshot) -> some View {
        let title = snapshot.displayTitle(for: player, chosen: identity.titleID)
        if isMe {
            Button {
                isPickingTitle = true
            } label: {
                HStack(spacing: 4) {
                    if let title {
                        TitleLabel(title: title, voice: voice)
                    } else {
                        Text("Pick a Title").kedroFont(.label).foregroundStyle(.silver)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.kedroRed)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title.map { "Title: \(voice.line($0.copyID))" } ?? "No title")
            .accessibilityHint("Changes your title")
        } else if let title {
            VStack(spacing: 2) {
                TitleLabel(title: title, voice: voice)
                Text(voice.line(title.taglineID))
                    .font(.caption)
                    .foregroundStyle(.silverDim)
            }
        }
    }

    /// "#13 GLOBAL · 1,086 · +18 TONIGHT". The rank and rating are the server's when loaded (the
    /// same on every phone); this phone's replay of its own games stands in offline.
    @ViewBuilder
    private func rankLine(record: PlayerRecord, snapshot: StatsSnapshot) -> some View {
        let remote = server.profile(player)
        if record.isRanked || remote?.globalRank != nil {
            let globalRank = remote?.globalRank.map { "\($0)" } ?? snapshot.ratingRank(of: player, scope: .global)?.label
            let rating = remote?.rating ?? record.displayRating
            let last = record.results.last
            HStack(spacing: 6) {
                if let globalRank {
                    Text("#\(globalRank) Global").foregroundStyle(.silver)
                    Text("·").foregroundStyle(.silverDim)
                }
                Text(rating.formatted()).foregroundStyle(.cream)
                if let last, last.gamesBefore + 1 > Ratings.rankedAfterGames {
                    Text("·").foregroundStyle(.silverDim)
                    Text("\(ScoreFormat.signed(last.ratingDelta)) \(Calendar.current.isDateInToday(last.date) ? "tonight" : "last game")")
                        .foregroundStyle(.kedroRed)
                }
            }
            .kedroFont(.label)
            .accessibilityElement(children: .combine)
        }
    }

    /// The server's rank line for someone with no games on this phone.
    @ViewBuilder
    private func serverRankLine(_ remote: PlayerProfileResponse) -> some View {
        if let rating = remote.rating {
            HStack(spacing: 6) {
                if let rank = remote.globalRank {
                    Text("#\(rank) Global").foregroundStyle(.silver)
                    Text("·").foregroundStyle(.silverDim)
                }
                Text(rating.formatted()).foregroundStyle(.cream)
            }
            .kedroFont(.label)
            .accessibilityElement(children: .combine)
        }
        if let games = remote.stats?.gamesPlayed, games < Ratings.rankedAfterGames {
            ProgressMeter(value: games)
        }
    }

    /// Lifetime numbers from the server (every finished game, not just this phone's).
    private func lifetime(_ stats: PlayerProfileResponse.Stats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StatsSectionHeader(title: "At a glance")
            HStack(spacing: 8) {
                StatTile(value: "\(stats.gamesPlayed)", caption: "Games", info: .gamesPlayed)
                StatTile(value: "\(stats.wins)", caption: "Wins", info: .wins)
                StatTile(value: StatsFormat.percent(stats.winRate), caption: "Win rate", info: .winRate)
                StatTile(value: stats.knockSuccess.map { StatsFormat.percent($0) } ?? "–", caption: "Knocks", info: .knockSuccess)
            }
        }
    }

    /// Form: the last five finishes, oldest first ("2·1·3·2·1"), wins in gold.
    @ViewBuilder
    private func form(_ record: PlayerRecord) -> some View {
        let recent = Array(record.results.suffix(5))
        if !recent.isEmpty {
            HStack(spacing: 8) {
                Text("Form").font(.caption2).foregroundStyle(.silverDim)
                HStack(spacing: 4) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { offset, result in
                        if offset > 0 { Text("·").foregroundStyle(.silverDim) }
                        Text(result.rank.label).foregroundStyle(result.isWinner ? .gold : .cream)
                    }
                }
                .kedroFont(.headline)
                InfoButton(definition: .form)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Form, last five finishes: \(recent.map(\.rank.ordinal).joined(separator: ", "))")
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(identity: StatsParticipant, snapshot: StatsSnapshot) -> some View {
        let lastShared = me.flatMap { me in snapshot.games.last { $0.contains(snapshot.options.canonical(me)) && $0.contains(snapshot.options.canonical(player)) } }
        if let me, !player.isGuest || lastShared != nil {
            VStack(spacing: 10) {
                Button(Literal.playAgain(with: identity.name)) {
                    Task {
                        do { try await app.playAgain(with: [identity]) } catch { playAgainFailed = true }
                    }
                }
                .buttonStyle(.kedroPrimary)
                .disabled(app.liveGame != nil || app.profile == nil)
                HStack(spacing: 10) {
                    if let lastShared {
                        Button(Literal.text("button.sendReceipt")) { receiptGame = ReceiptTarget(id: lastShared.id) }
                            .buttonStyle(.kedroGlassWide)
                    }
                    NavigationLink(value: AppRoute.headToHead(me, player)) {
                        Text("Head to Head")
                    }
                    .buttonStyle(.kedroGlassWide)
                }
            }
        }
    }

    // MARK: Sections

    private func atAGlance(_ stats: PlayerStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StatsSectionHeader(title: "At a glance")
            HStack(spacing: 8) {
                StatTile(value: "\(stats.gamesPlayed)", caption: "Games", info: .gamesPlayed)
                StatTile(value: "\(stats.wins)", caption: "Wins", info: .wins)
                StatTile(value: stats.winRate.map { StatsFormat.percent($0) } ?? "–", caption: "Win rate", info: .winRate)
                StatTile(value: stats.averageScorePerRound.map(StatsFormat.decimal) ?? "–", caption: "Avg / rd", info: .averageRound)
            }
        }
    }

    private func streaks(_ stats: PlayerStats) -> some View {
        StatsCard(title: "Streaks") {
            StatRow("Current win streak", value: "\(stats.currentWinStreak)", info: .currentStreak)
            Divider().overlay(Color.rule)
            StatRow("Longest win streak", value: "\(stats.longestWinStreak)", info: .longestStreak)
        }
    }

    private func knocking(_ stats: PlayerStats) -> some View {
        StatsCard(title: "Knocking") {
            StatRow(label: "\(stats.knocks) knocks · \(stats.knockRate.map { StatsFormat.percent($0) } ?? "0%") of rounds", info: .knockRate) {
                KnockTallyView(tally: KnockTally(landed: stats.landed, tied: stats.tied, failed: stats.failed))
            }
            Divider().overlay(Color.rule)
            StatRow("Success rate", value: stats.knockSuccessRate.map { StatsFormat.percent($0) } ?? "–", info: .knockSuccess)
            Divider().overlay(Color.rule)
            StatRow("Inherent knocks", value: "\(stats.inherentKnocks) · \(stats.inherentKnocksLanded) at −10", info: .inherentKnocks)
        }
    }

    private func games(_ stats: PlayerStats) -> some View {
        StatsCard(title: "Games") {
            gameMarkRow("Best game", mark: stats.bestGame, info: .bestGame)
            Divider().overlay(Color.rule)
            gameMarkRow("Worst game", mark: stats.worstGame, info: .worstGame)
            Divider().overlay(Color.rule)
            StatRow("Average per game", value: stats.averageScorePerGame.map(StatsFormat.decimal) ?? "–", info: .averageGame)
        }
    }

    @ViewBuilder
    private func gameMarkRow(_ label: String, mark: PlayerStats.GameMark?, info: StatDefinition) -> some View {
        if let mark {
            NavigationLink(value: AppRoute.gameHistory(mark.gameID)) {
                StatRow(label: label, info: info) {
                    HStack(spacing: 6) {
                        Text(mark.tableWord).font(.caption).foregroundStyle(.silverDim)
                        Text(ScoreFormat.string(mark.score)).fontWeight(.semibold)
                    }
                }
            }
            .buttonStyle(.plain)
        } else {
            StatRow(label, value: "–", info: info)
        }
    }

    @ViewBuilder
    private func rivalry(_ stats: PlayerStats, snapshot: StatsSnapshot) -> some View {
        let rivals = snapshot.rivals(of: player)
        if stats.nemesis != nil || !rivals.isEmpty {
            StatsCard(title: "Rivalry", info: .nemesis) {
                if let nemesis = stats.nemesis {
                    NavigationLink(value: AppRoute.headToHead(player, nemesis)) {
                        HStack(spacing: 12) {
                            StatsAvatar(identity: snapshot.identity(of: nemesis), ref: nemesis)
                            Text(nemesisLine(nemesis: nemesis, count: stats.nemesisCount, snapshot: snapshot))
                                .font(.subheadline)
                                .foregroundStyle(.cream)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.silverDim)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(rivals.filter { $0 != stats.nemesis }, id: \.self) { rival in
                    Divider().overlay(Color.rule)
                    rivalRow(rival, snapshot: snapshot)
                }
            }
        }
    }

    /// R-05 in the viewer's voice; for someone else's profile, the literal fact.
    private func nemesisLine(nemesis: PlayerRef, count: Int, snapshot: StatsSnapshot) -> String {
        let name = snapshot.name(of: nemesis)
        if isMe { return voice.line("R-05", ["name": name, "n": count]) }
        return "Nemesis: \(name), ahead \(count) times."
    }

    private func rivalRow(_ rival: PlayerRef, snapshot: StatsSnapshot) -> some View {
        let h2h = snapshot.headToHead(player, rival)
        return NavigationLink(value: AppRoute.headToHead(player, rival)) {
            HStack(spacing: 12) {
                StatsAvatar(identity: snapshot.identity(of: rival), ref: rival)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.name(of: rival)).font(.subheadline.weight(.semibold)).foregroundStyle(.cream)
                    Text("\(h2h.gamesTogether) games together").font(.caption).foregroundStyle(.silverDim)
                }
                Spacer()
                Text("\(h2h.aAhead)–\(h2h.bAhead)").kedroFont(.headline).foregroundStyle(.cream)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.silverDim)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(snapshot.name(of: rival)), \(h2h.gamesTogether) games together, \(h2h.aAhead) to \(h2h.bAhead)")
    }

    private func badges(_ record: PlayerRecord) -> some View {
        let earned = BadgeDefinition.all.filter { record.badges[$0.id] != nil }
            .sorted { lhs, rhs in
                if lhs.tier != rhs.tier { return lhs.tier > rhs.tier }
                return (record.badges[lhs.id]?.gameIndex ?? 0) > (record.badges[rhs.id]?.gameIndex ?? 0)
            }
        return NavigationLink(value: AppRoute.badges(player)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StatsSectionHeader(title: "Bragging rights", trailing: "\(earned.count) of \(BadgeDefinition.all.count)")
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.silverDim)
                }
                if earned.isEmpty {
                    Text("Nothing yet. Finish a game.").font(.subheadline).foregroundStyle(.silverDim)
                } else {
                    HStack(spacing: 10) {
                        ForEach(earned.prefix(5), id: \.id) { badge in
                            BadgeCoin(badge: badge.id, isEarned: true, size: 52, showsCategory: false)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surface, in: .rect(cornerRadius: 16))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bragging rights, \(earned.count) of \(BadgeDefinition.all.count) badges")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func shame(_ snapshot: StatsSnapshot) -> some View {
        let entries = snapshot.shameEntries(of: player, viewer: me ?? player)
        if !entries.isEmpty {
            NavigationLink(value: AppRoute.hallOfShame) {
                HStack {
                    Text(entries.count == 1 ? "1 entry in the Hall of Shame" : "\(entries.count) entries in the Hall of Shame")
                        .font(.subheadline)
                        .foregroundStyle(.cream)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.silverDim)
                }
                .padding(14)
                .background(.surface, in: .rect(cornerRadius: 16))
                .contentShape(.rect(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    /// You → Wrapped: the current one, plus past years (design §12.9).
    @ViewBuilder
    private func wrapped(_ snapshot: StatsSnapshot) -> some View {
        let years = snapshot.wrappedYears(for: player)
        if !years.isEmpty {
            StatsCard(title: "Kedro Wrapped") {
                ForEach(years, id: \.self) { year in
                    NavigationLink(value: AppRoute.wrapped(year: year)) {
                        HStack {
                            Text(voice.line("WR-01", ["year": String(year)])).font(.subheadline).foregroundStyle(.cream)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.silverDim)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if year != years.last { Divider().overlay(Color.rule) }
                }
            }
        }
    }

    private func history(_ record: PlayerRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StatsSectionHeader(title: "History", trailing: "\(record.gamesPlayed)")
            LazyVStack(spacing: 0) {
                ForEach(record.results.reversed()) { result in
                    NavigationLink(value: AppRoute.gameHistory(result.gameID)) {
                        HistoryRow(result: result)
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Color.rule)
                }
            }
            .padding(.horizontal, 14)
            .background(.surface, in: .rect(cornerRadius: 16))
        }
    }
}

/// The game a receipt is sent from (a sheet item).
struct ReceiptTarget: Identifiable, Hashable {
    let id: GameID
}

/// A card with a Bebas header and rows.
struct StatsCard<Content: View>: View {
    let title: String
    var info: StatDefinition?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                StatsSectionHeader(title: title)
                if let info { InfoButton(definition: info) }
            }
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.surface, in: .rect(cornerRadius: 16))
        }
    }
}

/// One game in a profile's history, with its rating change.
private struct HistoryRow: View {
    let result: PlayerGameResult

    var body: some View {
        HStack(spacing: 12) {
            Text(result.rank.label)
                .kedroFont(.headline)
                .foregroundStyle(result.isWinner ? .gold : .cream)
                .frame(minWidth: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.tableWord).font(.subheadline.weight(.semibold)).foregroundStyle(.cream)
                Text("\(result.date.formatted(.dateTime.month(.abbreviated).day())) · \(result.playerCount) players · \(result.roundsPlayed) rounds")
                    .font(.caption)
                    .foregroundStyle(.silverDim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ScoreFormat.string(result.finalScore)).kedroFont(.headline).foregroundStyle(.cream)
                if result.gamesBefore + 1 >= Ratings.rankedAfterGames {
                    Text(ScoreFormat.signed(result.ratingDelta)).font(.caption).foregroundStyle(.silver)
                }
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.silverDim)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "\(result.tableWord), \(result.date.formatted(date: .abbreviated, time: .omitted)), finished \(result.rank.ordinal), \(ScoreFormat.spoken(result.finalScore)) points"
        if result.gamesBefore + 1 >= Ratings.rankedAfterGames { text += ", rating \(ScoreFormat.spoken(result.ratingDelta))" }
        return text
    }
}

extension StatsSnapshot {
    /// Years with a Wrapped a person can open now, newest first.
    func wrappedYears(for ref: PlayerRef, now: Date = .now) -> [Int] {
        guard let record = record(ref) else { return [] }
        let years = Set(record.results.map { calendar.component(.year, from: $0.date) })
        return years.sorted(by: >).filter { wrappedAvailability(for: ref, year: $0, now: now) == .available }
    }
}

#Preview("You") {
    NavigationStack { ProfileView(player: PreviewData.noah.ref).appRouteDestinations() }
        .previewEnvironment()
}

#Preview("Someone else") {
    NavigationStack { ProfileView(player: PreviewData.ana.ref).appRouteDestinations() }
        .previewEnvironment()
}

#Preview("Unranked guest") {
    NavigationStack { ProfileView(player: .guest(PreviewData.samID)).appRouteDestinations() }
        .previewEnvironment()
}
