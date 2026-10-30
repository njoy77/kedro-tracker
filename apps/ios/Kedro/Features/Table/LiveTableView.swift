import SwiftUI

/// The Table while a game is being played (design §6): toolbar with the metadata line, the
/// last-round card, standings, banter and the bottom bar. Rotating to landscape (or ⋯ → Table
/// Display, or any iPad) switches to display mode. Owns every sheet the Table presents.
struct LiveTableView: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(LiveActivityController.self) private var liveActivity: LiveActivityController?
    @State private var talk = TalkServices.shared
    @State private var sheet: TableSheet?
    @State private var confirmation: Confirmation?
    @State private var isEndingGame = false
    @State private var nextDealerNudge: String?
    /// nil follows the device (landscape or iPad); true/false is the ⋯ menu's choice.
    @State private var displayModeChoice: Bool?
    @State private var banner: TableBanner?
    @State private var revealClock = Date.now

    private enum Confirmation: Identifiable {
        case abandon
        var id: Self { self }
    }

    /// How long "Next deal: Ana." stays on the last-round card (design §6.4).
    static let nudgeDuration: Duration = .seconds(5)

    var body: some View {
        Group {
            if isDisplayMode {
                DisplayModeView(
                    session: session,
                    banner: $banner,
                    onRecord: canRecord ? { sheet = .record } : nil,
                    onExit: { displayModeChoice = false }
                )
            } else {
                NavigationStack {
                    table
                        .toolbar { toolbar }
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .onChange(of: sheet) { _, presented in
            // Nothing covers the Round sheet: toasts queue until it closes (design §6.5).
            app.toasts.isDeferring = presented == .record
        }
        .endGameDialog(session, isPresented: $isEndingGame)
        .alert(confirmationTitle, isPresented: isConfirming, presenting: confirmation) { kind in
            confirmationButtons(kind)
        } message: { kind in
            Text(confirmationMessage(kind))
        }
        .tableAttention(session, isDisplayMode: isDisplayMode, banner: $banner) { tab in
            sheet = .history(tab)
        }
        .selfReportAutoCommit(session)
        .keepsScreenAwake()
        // A tapped taunt toast (Talk) asks for the feed: open History on the Feed tab.
        .onChange(of: talk.feedRequest, initial: true) { _, request in
            guard request == session.gameID else { return }
            talk.feedRequest = nil
            sheet = .history(.feed)
        }
        // Live Activity buttons (Record Round / Report Your Hand) land here.
        .onChange(of: liveActivity?.pendingAction, initial: true) {
            takeLiveActivityAction()
        }
        .onChange(of: isDisplayMode, initial: true) { _, isOn in
            displayModeChanged(isOn)
        }
        .onChange(of: verticalSizeClass) { displayModeChoice = nil }
        .onChange(of: session.state.rounds.count) { old, new in
            guard new > old, let dealer = session.state.currentDealer else {
                nextDealerNudge = nil
                return
            }
            nextDealerNudge = session.state.name(of: dealer)
        }
        .task(id: nextDealerNudge) {
            guard nextDealerNudge != nil else { return }
            try? await Task.sleep(for: Self.nudgeDuration)
            guard !Task.isCancelled else { return }
            withAnimation { nextDealerNudge = nil }
        }
        .task(id: session.state.lastRound?.opId) {
            // The shared reveal (design §7.4): re-render when the hidden round flips.
            revealClock = .now
            guard let reveal = TableReveal.pendingRevealTime(state: session.state, now: .now) else { return }
            try? await Task.sleep(for: .seconds(max(0, reveal.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.35)) { revealClock = .now }
        }
        .task(id: session.state.isAwaitingFinish) { await autoFinish() }
        .onDisappear {
            app.toasts.isDeferring = false
            talk.bannerGames.remove(session.gameID)
        }
    }

    // MARK: System hooks

    private func takeLiveActivityAction() {
        guard let action = liveActivity?.takePendingAction(for: session.gameID) else { return }
        switch action {
        case .recordRound, .reportHand:
            if canRecord { sheet = .record }
        case .openTable:
            break
        }
    }

    /// Display mode shows taunts as banners (Talk skips the toast) and claims the table speaker,
    /// because the propped-up phone is the one everyone hears (design §3.8, §6.3).
    private func displayModeChanged(_ isOn: Bool) {
        if isOn {
            talk.bannerGames.insert(session.gameID)
            guard state.tableSpeaker != app.deviceID, state.status.isLive else { return }
            run { try await session.claimTableSpeaker() }
        } else {
            talk.bannerGames.remove(session.gameID)
        }
    }

    // MARK: Layout

    private var state: GameState { session.state }

    private var isDisplayMode: Bool {
        displayModeChoice ?? (verticalSizeClass == .compact || (horizontalSizeClass == .regular && verticalSizeClass == .regular))
    }

    private var isCompact: Bool { state.seats.count >= StandingsView.compactThreshold }

    /// 6–8 players from AX2: the list scrolls and your row pins above the bottom bar (design §6.2).
    private var pinnedSeat: SeatID? {
        guard isCompact, dynamicTypeSize >= .accessibility2 else { return nil }
        return session.mySeatID
    }

    private var table: some View {
        let visible = TableReveal.visibleState(state: state, operations: session.operations, now: revealClock)
        let voice = app.houseVoice(for: state)
        return ScrollView {
            tableContent(visible: visible, voice: voice)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.night.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomInset(visible: visible)
        }
    }

    private func tableContent(visible: (state: GameState, isHidden: Bool), voice: Voice) -> some View {
        VStack(spacing: 14) {
            SyncPill(syncState: app.transport.syncState, voice: voice)
            selfReportCard
            LastRoundCard(
                state: visible.state,
                voice: voice,
                mySeat: session.mySeatID,
                viewerIsLearner: viewerIsLearner,
                nextDealer: nextDealerNudge,
                isHidden: visible.isHidden,
                compact: isCompact,
                onWhy: { sheet = .why($0) },
                onReact: session.mySeatID == nil ? nil : { react($0) }
            )
            StandingsView(
                state: visible.state,
                mySeat: session.mySeatID,
                hidesDeltas: visible.isHidden,
                excluding: pinnedSeat,
                onDealerTap: session.canEdit ? { sheet = .dealer } : nil
            )
            if !visible.isHidden, let banter = TableVoice.banter(for: state) {
                Text(banter.render(voice, gameID: state.gameID, round: state.rounds.count))
                    .kedroFont(.roast)
                    .foregroundStyle(.silver)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
                    .id(state.rounds.count)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .animation(.smooth(duration: 0.3), value: nextDealerNudge)
    }

    private func bottomInset(visible: (state: GameState, isHidden: Bool)) -> some View {
        VStack(spacing: 0) {
            if let pinnedSeat, let standing = visible.state.standing(for: pinnedSeat) {
                StandingRow(standing: standing, isMe: true, compact: true, hidesDelta: visible.isHidden, showsLeader: !state.rounds.isEmpty)
                    .padding(.horizontal, 16)
                    .background(.surface)
            }
            bottomBar
        }
    }

    @ViewBuilder
    private var selfReportCard: some View {
        if state.config.scoringMode == .selfReport, state.status == .active {
            let resolution = KnockerResolution.evaluate(state.selfReport, seats: state.seats.map(\.id), now: .now)
            if resolution.needsDecision {
                KnockerDecisionView(session: session)
            } else if case .collecting(let waitingOn) = resolution, let report = state.selfReport, !report.hands.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(TableText.text("label.reportStatus", ["r": report.roundNumber, "done": report.hands.count, "total": state.seats.count]))
                        .kedroFont(.label)
                        .foregroundStyle(.silver)
                    Text(app.houseVoice(for: state).line("K-14", ["names": ListFormatter.localizedString(byJoining: waitingOn.map(state.name(of:)))]))
                        .font(.callout)
                        .foregroundStyle(.cream)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.surface, in: .rect(cornerRadius: 18))
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(TableText.text("button.minimize"), systemImage: "chevron.down") { app.minimizeTable() }
        }
        ToolbarItem(placement: .principal) {
            Button {
                sheet = .dealer
            } label: {
                TableToolbarTitle(
                    round: Literal.roundOf(state.progress.currentRound, state.config.plannedRounds),
                    word: state.config.tableWord,
                    dealer: state.currentDealer.map { state.name(of: $0) }
                )
            }
            .buttonStyle(.plain)
            .disabled(!session.canEdit)
            .accessibilityHint(session.canEdit ? TableText.text("button.changeDealer") : "")
        }
        // Three buttons at most, so the metadata line keeps the table word and dealer readable on a
        // 6.1" phone: End Game takes Rules' place for anyone who can end the game (Rules moves to
        // the top of More).
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(TableText.text("button.history"), systemImage: "clock.arrow.circlepath") { sheet = .history(.scores) }
            if session.canEdit {
                Button(Literal.text("button.endGame"), systemImage: "flag.checkered") { isEndingGame = true }
            } else {
                Button(TableText.text("button.rules"), systemImage: "questionmark") { sheet = .rules }
            }
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            if session.canEdit {
                Button(TableText.text("button.rules"), systemImage: "questionmark.circle") { sheet = .rules }
            }
            // Seats stay open until Round 1 (and a guest's late phone can take over its seat any
            // time), so the rotating QR stays reachable after Deal for App Clip guests and phones
            // that can't see the table (design §5.9 rows 5, 8 and 10).
            if state.status.isLive {
                Button(TableText.text("button.invite"), systemImage: "qrcode") { sheet = .invite }
            }
            Button(TableText.text("button.tableDisplay"), systemImage: "rectangle.landscape.rotate") { displayModeChoice = true }
            if session.canEdit {
                Button(TableText.text("button.changeDealer"), systemImage: "arrow.triangle.2.circlepath") { sheet = .dealer }
                if state.config.scoringMode == .scorekeeper {
                    Button(TableText.text("button.handOff"), systemImage: "person.crop.circle.badge.checkmark") { sheet = .handOff }
                }
            }
            if state.tableSpeaker == app.deviceID {
                Label(TableText.text("label.youreTableSpeaker"), systemImage: "hifispeaker.fill")
            } else {
                Button(TableText.text("button.tableSpeaker"), systemImage: "hifispeaker") {
                    run { try await session.claimTableSpeaker() }
                }
            }
            if session.canEdit {
                Section {
                    Button(Literal.text("button.extend"), systemImage: "plus.circle") { sheet = .extend }
                    if state.seats.count < GameConfig.seatRange.upperBound, !state.isAwaitingFinish {
                        Button(Literal.text("button.addPlayer"), systemImage: "person.badge.plus") { sheet = .addPlayer }
                    }
                    Button(Literal.text("button.endGame"), systemImage: "flag.checkered") { isEndingGame = true }
                    Button(Literal.text("button.abandon"), systemImage: "xmark.octagon", role: .destructive) { confirmation = .abandon }
                }
            }
        } label: {
            Label(TableText.text("button.more"), systemImage: "ellipsis")
        }
    }

    // MARK: Bottom bar

    private var canRecord: Bool { state.status == .active && session.mySeatID != nil }

    private var bottomBar: some View {
        TableBottomBar(
            primary: primaryAction,
            caption: caption,
            isKnockMarked: state.liveKnock != nil,
            canKnock: canRecord && !state.isAwaitingFinish,
            canTalk: state.status.isLive,
            onKnock: { sheet = .liveKnock },
            onTalk: { sheet = .talk(defaultTauntTarget) }
        )
    }

    private var primaryAction: TableBottomBar.Primary? {
        guard canRecord, let me = session.mySeatID else { return nil }
        if state.isAwaitingFinish {
            return .init(title: Literal.text("button.finishGame"), isProminent: true) { sheet = .record }
        }
        switch state.config.scoringMode {
        case .scorekeeper:
            return .init(title: Literal.recordRound(state.nextRoundNumber), isProminent: session.isScorekeeper) { sheet = .record }
        case .selfReport:
            let reported = state.selfReport?.hands ?? [:]
            let pending = GuestReporters.seats(reportedBy: me, in: state.seats).filter { reported[$0] == nil }
            if pending.isEmpty {
                let waiting = state.selfReport?.waitingOn.count ?? state.seats.count
                return .init(title: TableText.text("label.youReported", ["n": waiting]), isProminent: false) { sheet = .record }
            }
            return .init(title: Literal.text("button.reportHand"), isProminent: true) { sheet = .record }
        }
    }

    private var caption: String {
        guard state.status == .active else { return TableText.text("label.lobbyWaiting") }
        guard session.mySeatID != nil else { return TableText.text("label.watching") }
        if state.isAwaitingFinish { return TableText.text("label.waitingOnFinish") }
        switch state.config.scoringMode {
        case .scorekeeper:
            if let mark = state.liveKnock {
                return TableText.text("label.knockerPrefilled", ["name": state.name(of: mark.knocker)])
            }
            if session.isScorekeeper { return Literal.text("label.keepingScore") }
            return TableText.text("label.keepingScoreOther", ["name": state.scorekeeper.map(state.name(of:)) ?? "Someone"])
        case .selfReport:
            return TableText.text("label.everyoneReports")
        }
    }

    /// Talk's default target: whoever just did something roastable, otherwise the table (§8.1).
    private var defaultTauntTarget: TauntTarget {
        let me = session.mySeatID
        if let mark = state.liveKnock, mark.knocker != me { return .seat(mark.knocker) }
        if let last = state.lastRound, last.outcome == .failed, let knocker = last.knocker, knocker != me { return .seat(knocker) }
        return .table
    }

    private var viewerIsLearner: Bool {
        guard let seat = session.mySeat else { return false }
        return prefs.showsLearnerHints(gamesPlayed: seat.gamesPlayed ?? 0)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: TableSheet) -> some View {
        switch sheet {
        case .record:
            RoundSheet(session: session) {
                self.sheet = .history(.scores)
            }
        case .history(let tab):
            NavigationStack {
                HistorySheet(session: session, initialTab: tab)
                    .navigationTitle(TableText.text("button.history"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(Literal.text("button.done")) { self.sheet = nil }
                        }
                    }
            }
            .toastHost(app.toasts)
            .presentationDragIndicator(.visible)
        case .talk(let target):
            TalkSheet(session: session, target: target)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .rules:
            NavigationStack { RulesSheet().appRouteDestinations() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .why(let round):
            NavigationStack { KnockCalculatorView(prefill: round).appRouteDestinations() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .dealer:
            DealerPickerSheet(session: session)
        case .liveKnock:
            LiveKnockSheet(session: session)
        case .handOff:
            HandOffSheet(session: session)
        case .extend:
            ExtendSheet(session: session)
        case .addPlayer:
            LateJoinSheet(session: session)
        case .invite:
            InviteQRSheet(
                token: TableTokenVault.token(for: session.gameID),
                tableWord: state.config.tableWord,
                hostName: state.hostSeat.flatMap { state.seat($0)?.displayName } ?? session.mySeat?.displayName ?? ""
            )
        case .receipt:
            ReceiptComposer(gameID: session.gameID)
        }
    }

    // MARK: Confirmations

    private var isConfirming: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .abandon: Literal.text("button.abandon")
        case nil: ""
        }
    }

    private func confirmationMessage(_ kind: Confirmation) -> String {
        let voice = app.houseVoice(for: state)
        return switch kind {
        case .abandon: voice.line("G-04")
        }
    }

    @ViewBuilder
    private func confirmationButtons(_ kind: Confirmation) -> some View {
        switch kind {
        case .abandon:
            Button(Literal.text("button.abandon"), role: .destructive) { run { try await session.abandon() } }
        }
        Button(TableText.text("button.cancel"), role: .cancel) {}
    }

    // MARK: Actions

    private func react(_ reaction: Reaction) {
        run { try await session.react(reaction) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        let toasts = app.toasts
        Task {
            do { try await work() } catch { toasts.show(error.localizedDescription) }
        }
    }

    /// Auto-finish after 15 idle minutes on the finish gate (design §9.3, G-02). The scorekeeper's
    /// phone does it; other seated phones back it up two minutes later (a duplicate would only
    /// be logged as late).
    private func autoFinish() async {
        guard session.state.isAwaitingFinish, let me = session.mySeatID else { return }
        let grace: TimeInterval = me == session.state.scorekeeper ? 0 : 120
        while !Task.isCancelled, session.state.isAwaitingFinish {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            _ = try? await session.finishIfIdle(now: .now.addingTimeInterval(-grace))
        }
    }
}

#Preview("After Round 5") {
    LiveTableView(session: PreviewData.sampleSession(throughRound: 5))
        .toastHost(AppModel.preview().toasts)
        .previewEnvironment(AppModel.preview(liveGame: true))
}

#Preview("Live knock marked") {
    LiveTableView(session: PreviewData.sampleSession(throughRound: 5, liveKnock: true))
        .previewEnvironment()
}

#Preview("8 players") {
    LiveTableView(session: TablePreviews.eightPlayerSession)
        .previewEnvironment()
}

#Preview("Self-report, waiting") {
    LiveTableView(session: TablePreviews.selfReportSession(reported: 3))
        .previewEnvironment()
}

#Preview("Fresh table") {
    LiveTableView(session: TablePreviews.freshSession)
        .previewEnvironment()
}
