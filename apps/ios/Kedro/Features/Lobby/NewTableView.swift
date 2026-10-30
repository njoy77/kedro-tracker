import SwiftUI

/// The lobby: seats, add players, rounds, scoring, Deal (design §5.6, mockup frame 5).
///
/// One grouped `List`, no wizard. Not a `NavigationStack` root: present it with
/// `.newTableSheet(_:)`, which wraps it in a stack, keeps it from being swiped away, and shows the
/// Table once the host deals.
struct NewTableView: View {
    private let start: LobbyStart

    /// A fresh table with this phone's person as host.
    init() {
        start = .fresh
    }

    /// Run It Back: same people, rounds and mode; the first deal rotates one seat (design §5.7).
    init(rematchOf previous: GameState) {
        start = .rematch(previous)
    }

    /// Reopens a lobby this phone already opened (the live game, still before Deal).
    init(session: GameSession) {
        start = .resume(session)
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: LobbyModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                LobbyForm(model: model) { dismiss() }
            } else if failed {
                ContentUnavailableView(
                    "No Profile Yet",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Set up your name first, then start a table.")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Literal.text("button.newTable"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil else { return }
            do {
                let lobby = try start.makeModel(app: app)
                model = lobby
                await lobby.load()
            } catch {
                failed = true
            }
        }
    }
}

/// How a lobby starts.
enum LobbyStart: Identifiable {
    case fresh
    case rematch(GameState)
    case resume(GameSession)

    var id: String {
        switch self {
        case .fresh: "fresh"
        case .rematch(let state): "rematch:\(state.gameID)"
        case .resume(let session): "resume:\(session.gameID)"
        }
    }

    func makeModel(app: AppModel) throws -> LobbyModel {
        switch self {
        case .fresh: try LobbyModel(app: app)
        case .rematch(let previous): try LobbyModel(app: app, rematchOf: previous)
        case .resume(let session): try LobbyModel(app: app, session: session)
        }
    }
}

extension View {
    /// Presents the lobby as a sheet. When the host deals, the sheet closes and the Table opens
    /// full screen (a cover can't be presented while the sheet is still on screen).
    func newTableSheet(_ start: Binding<LobbyStart?>) -> some View {
        modifier(NewTableSheetModifier(start: start))
    }
}

private struct NewTableSheetModifier: ViewModifier {
    @Binding var start: LobbyStart?
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.sheet(item: $start, onDismiss: presentTableIfDealt) { start in
            NavigationStack {
                Group {
                    switch start {
                    case .fresh: NewTableView()
                    case .rematch(let previous): NewTableView(rematchOf: previous)
                    case .resume(let session): NewTableView(session: session)
                    }
                }
                .appRouteDestinations()
            }
            .interactiveDismissDisabled()
            .toastHost(app.toasts)
        }
    }

    private func presentTableIfDealt() {
        if app.liveGame?.state.status == .active { app.presentTable() }
    }
}

// MARK: - The form

private struct LobbyForm: View {
    let model: LobbyModel
    var close: () -> Void

    @Environment(AppModel.self) private var app
    @State private var editMode: EditMode = .inactive
    @State private var adding: AddRoute?
    @State private var isInviting = false
    @State private var isCustomRounds = false
    @State private var isDealing = false

    enum AddRoute: String, Identifiable {
        case playedWith, search, guest
        var id: String { rawValue }
    }

    var body: some View {
        List {
            tableSection
            seatsSection
            addSection
            gameSection
            stakesSection
            dealSection
        }
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    Task {
                        await model.cancel()
                        close()
                    }
                }
                .disabled(isDealing)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(Literal.text("button.deal"), action: deal)
                    .buttonStyle(.borderedProminent)
                    .tint(.kedroRed)
                    .disabled(!model.canDeal || isDealing)
            }
        }
        .sheet(item: $adding) { route in
            switch route {
            case .playedWith: PlayedWithSheet(model: model)
            case .search: SearchKedroSheet(model: model)
            case .guest: GuestSheet(model: model)
            }
        }
        .sheet(isPresented: $isInviting) {
            if let token = model.inviteToken {
                InviteQRSheet(token: token, tableWord: model.config.tableWord, hostName: model.hostName)
            }
        }
        .onChange(of: model.seats.map(\.id)) { announceArrivals() }
        .task(id: model.gameID) { await followSeatRequests() }
        .onAppear { isCustomRounds = !GameConfig.roundPresets.contains(model.plannedRounds) }
    }

    // MARK: Table

    private var tableSection: some View {
        Section("Table") {
            HStack(spacing: 12) {
                Text("\(model.hostName)'s table")
                    .foregroundStyle(.cream)
                Spacer()
                Text(model.config.tableWord.uppercased())
                    .kedroFont(.headline)
                    .foregroundStyle(.cream)
                    .accessibilityLabel("Table word: \(model.config.tableWord)")
                Button("New Table Word", systemImage: "arrow.clockwise") {
                    Task { await model.regenerateTableWord() }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.kedroRed)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.borderless)
                .disabled(!model.canChangeTableShape)
            }
        }
    }

    // MARK: Seats

    private var seatsSection: some View {
        Section {
            ForEach(model.seats) { seat in
                LobbySeatRow(seat: seat, model: model)
            }
            .onMove { source, destination in
                Task { await model.move(from: source, to: destination) }
            }
        } header: {
            HStack {
                Text("Seats · \(model.seats.count) of \(GameConfig.seatRange.upperBound)")
                Spacer()
                if model.seats.count > 1 {
                    Button(editMode.isEditing ? Literal.text("button.done") : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .font(.subheadline)
                    .textCase(nil)
                }
            }
        } footer: {
            Text("Clockwise around the table, which is also the dealing order.")
        }
    }

    // MARK: Add

    private var addSection: some View {
        Section {
            addRow("Played With", systemImage: "person.2") { adding = .playedWith }
                .disabled(!model.canAdd)
            addRow("Search Kedro", systemImage: "magnifyingglass", detail: "name or @handle") { adding = .search }
                .disabled(!model.canAdd)
            addRow("Guest", systemImage: "person.badge.plus") { adding = .guest }
                .disabled(!model.canAdd)
            addRow("Invite with QR or AirDrop", systemImage: "qrcode") {
                Task {
                    do {
                        try await model.open()
                        isInviting = true
                    } catch {
                        app.toasts.show(app.voice.line("E-01"))
                    }
                }
            }
        } footer: {
            if !model.canAdd {
                Text("The table's full at \(GameConfig.seatRange.upperBound).")
            }
        }
    }

    private func addRow(_ title: String, systemImage: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.kedroRed)
                Spacer()
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.silverDim)
                }
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
    }

    // MARK: Game

    private var gameSection: some View {
        Section {
            Picker("Rounds", selection: roundsChoice) {
                ForEach(GameConfig.roundPresets, id: \.self) { Text("\($0)").tag(Optional($0)) }
                Text("Custom").tag(Int?.none)
            }
            if isCustomRounds {
                Stepper(value: plannedRounds, in: GameConfig.plannedRoundsRange) {
                    Text("\(model.plannedRounds) rounds")
                }
            }

            Picker("First deal", selection: firstDealer) {
                ForEach(model.seats) { seat in
                    Text(seat.id == model.hostSeatID ? "\(seat.displayName) (host)" : seat.displayName).tag(seat.id)
                }
            }

            Picker("Scoring", selection: scoringMode) {
                Text("Scorekeeper").tag(ScoringMode.scorekeeper)
                Text("Everyone Reports").tag(ScoringMode.selfReport)
            }
            .disabled(!model.canChangeTableShape)

            houseVoiceRow
        } header: {
            Text("Game")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if model.config.scoringMode == .selfReport {
                    Text("Everyone types their own hand. Guests without the app need someone to report for them.")
                } else {
                    Text("One phone enters every hand.")
                }
                if model.houseVoiceLowered {
                    Text(app.voice.line("J-15", ["level": model.houseLevel.displayName]))
                }
                if !model.canChangeTableShape {
                    Text("Someone's sat down, so the table word, scoring and house voice are set.")
                }
            }
        }
    }

    private var houseVoiceRow: some View {
        HStack {
            Text("House voice")
            Spacer()
            let lower = LanguageLevel.allCases.filter { $0 < model.houseLevel }
            if lower.isEmpty || !model.canChangeTableShape {
                Text(model.houseLevel.displayName).foregroundStyle(.silver)
            } else {
                Menu {
                    Section("Keep it cleaner tonight") {
                        ForEach(lower) { level in
                            Button(level.displayName) { Task { await model.capHouseVoice(at: level) } }
                        }
                    }
                    if model.config.houseVoiceCap != nil {
                        Button("No Cap") { Task { await model.capHouseVoice(at: nil) } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.houseLevel.displayName)
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .foregroundStyle(.silver)
                }
                .accessibilityLabel("House voice, \(model.houseLevel.displayName). Keep it cleaner tonight.")
            }
        }
        .frame(minHeight: 44)
    }

    private var roundsChoice: Binding<Int?> {
        Binding {
            isCustomRounds ? nil : model.plannedRounds
        } set: { choice in
            if let choice {
                isCustomRounds = false
                Task { await model.setPlannedRounds(choice) }
            } else {
                isCustomRounds = true
            }
        }
    }

    private var plannedRounds: Binding<Int> {
        Binding { model.plannedRounds } set: { rounds in Task { await model.setPlannedRounds(rounds) } }
    }

    private var firstDealer: Binding<SeatID> {
        Binding { model.firstDealer ?? model.hostSeatID } set: { model.firstDealer = $0 == model.hostSeatID ? nil : $0 }
    }

    private var scoringMode: Binding<ScoringMode> {
        Binding { model.config.scoringMode } set: { mode in Task { await model.setScoringMode(mode) } }
    }

    // MARK: Stakes and Deal

    @ViewBuilder
    private var stakesSection: some View {
        let lines = model.stakes.filter { $0 != .nothing }
        if !lines.isEmpty {
            Section("Stakes") {
                ForEach(lines, id: \.self) { line in
                    Text(line.text(app.voice))
                        .font(.subheadline)
                        .foregroundStyle(.cream)
                }
            }
        }
    }

    private var dealSection: some View {
        Section {
            Button(action: deal) {
                if isDealing {
                    ProgressView().tint(.white)
                } else {
                    Text(Literal.text("button.deal"))
                }
            }
            .buttonStyle(.kedroPrimary)
            .disabled(!model.canDeal || isDealing)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            if let issue = model.issues.first {
                Text(issue.message(app.voice, seats: model.seats))
                    .font(.footnote)
                    .foregroundStyle(.silver)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
        }
    }

    private func deal() {
        guard model.canDeal, !isDealing else { return }
        isDealing = true
        Task {
            defer { isDealing = false }
            do {
                try await model.deal()
                close()
            } catch {
                app.toasts.show(error.localizedDescription)
            }
        }
    }

    // MARK: Other phones

    /// "Ana sat down. · Remove" for people who sat down from their own phone (J-03).
    private func announceArrivals() {
        for seat in model.takeArrivals() {
            app.toasts.show(Toast(
                avatar: seat.avatar,
                avatarName: seat.displayName,
                avatarIsGuest: seat.isGuest,
                message: app.voice.line("J-03", ["name": seat.displayName]),
                action: Toast.Action(title: Literal.text("button.remove")) {
                    Task { await model.remove(seat.id) }
                },
                duration: .seconds(5)
            ))
        }
    }

    /// Ask to Sit from strangers (J-02): the host lets them in with one tap.
    private func followSeatRequests() async {
        guard let requests = model.seatRequests() else { return }
        for await seat in requests where !model.isSeated(seat.player) {
            app.toasts.show(Toast(
                avatar: seat.avatar,
                avatarName: seat.displayName,
                avatarIsGuest: seat.isGuest,
                message: app.voice.line("J-02", ["name": seat.displayName]),
                action: Toast.Action(title: Literal.letIn(seat.displayName)) {
                    Task { await model.add(seat) }
                },
                duration: .seconds(15)
            ))
        }
    }
}

// MARK: - A seat

/// Avatar, name, role line and the ⋯ menu (Make scorekeeper · Assign reporter · Move · Remove).
private struct LobbySeatRow: View {
    let seat: Seat
    let model: LobbyModel

    private var role: SeatRoleLine { model.roleLine(for: seat) }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(seat: seat, size: .compact)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(seat.displayName).foregroundStyle(.cream)
                    if seat.isGuest {
                        Text(Literal.text("label.guest")).font(.caption).foregroundStyle(.silverDim)
                    }
                }
                roleView
            }
            Spacer(minLength: 8)
            menu
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityActions { actions }
    }

    @ViewBuilder
    private var roleView: some View {
        if case .meter(let games) = role {
            ProgressMeter(value: games)
        } else {
            Text(role.text).font(.caption).foregroundStyle(.silver)
        }
    }

    private var accessibilityText: String {
        let parts: [String?] = [seat.displayName, seat.isGuest ? "guest" : nil, role.text]
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    private var menu: some View {
        Menu {
            actions
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.silver)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Options for \(seat.displayName)")
    }

    @ViewBuilder
    private var actions: some View {
        let config = model.config
        let index = model.seats.firstIndex(where: { $0.id == seat.id }) ?? 0
        if config.scoringMode == .scorekeeper, !seat.isGuest, (config.scorekeeperSeat ?? model.hostSeatID) != seat.id {
            Button("Make Scorekeeper", systemImage: "pencil.and.list.clipboard") {
                Task { await model.makeScorekeeper(seat.id) }
            }
        }
        if seat.isGuest {
            let reporters = model.seats.filter { !$0.isGuest }
            Menu("Assign Reporter") {
                ForEach(reporters) { reporter in
                    Button {
                        Task { await model.assignReporter(reporter.id, to: seat.id) }
                    } label: {
                        if seat.reporter == reporter.id {
                            Label(reporter.displayName, systemImage: "checkmark")
                        } else {
                            Text(reporter.displayName)
                        }
                    }
                }
                if seat.reporter != nil, config.scoringMode == .scorekeeper {
                    Button("Nobody") { Task { await model.assignReporter(nil, to: seat.id) } }
                }
            }
        }
        Menu("Move") {
            Button("Move Clockwise", systemImage: "arrow.down") {
                Task { await model.move(seat.id, by: 1) }
            }
            .disabled(index >= model.seats.count - 1)
            Button("Move Counter-clockwise", systemImage: "arrow.up") {
                Task { await model.move(seat.id, by: -1) }
            }
            .disabled(index == 0)
        }
        if seat.id != model.hostSeatID {
            Button(Literal.text("button.remove"), systemImage: "minus.circle", role: .destructive) {
                Task { await model.remove(seat.id) }
            }
        }
    }
}

// MARK: - Previews

#Preview("New Table") {
    NavigationStack { NewTableView() }
        .previewEnvironment()
}

#Preview("Run It Back") {
    NavigationStack { NewTableView(rematchOf: PreviewData.sampleState(throughRound: 8, finished: true)) }
        .previewEnvironment()
}
