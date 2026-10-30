import SwiftUI

/// Add Players (design §5.6): one list to pick from, before Deal or mid-game. Nearby people
/// first (hosts and players at tables this phone can see), then everyone you've played with,
/// then every other Kedro player A–Z, a page at a time. Typing filters the list and searches
/// Kedro by name or @handle. Pick several, then Add. Adding is the host vouching: they're seated
/// without Ask to Sit. "Add a Guest" covers people without the app.
struct AddPlayersSheet: View {
    let model: any SeatAdding

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var nearby: [PlayerSummary] = []
    @State private var playedWith: [PlayedWith] = []
    @State private var everyone: [PlayerSummary] = []
    @State private var nextPage: String?
    @State private var isLoadingPage = false
    @State private var searchResults: [PlayerSummary] = []
    @State private var selected: [PlayerID: PlayerSummary] = [:]
    @State private var isLoading = true
    @State private var isAddingGuest = false
    @State private var filter = ""

    private var room: Int { model.room }
    private var needle: String { filter.trimmingCharacters(in: .whitespaces).lowercased() }
    private var isSearching: Bool { needle.trimmingCharacters(in: CharacterSet(charactersIn: "@")).count >= RemotePlayerDirectory.minimumQueryLength }

    private func shows(_ player: PlayerSummary) -> Bool {
        guard player.ref != app.profile?.identity, !model.isUnavailable(player.ref) else { return false }
        let query = needle.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return query.isEmpty || player.displayName.lowercased().contains(query) || player.handle.rawValue.contains(query)
    }

    /// Each section leaves out anyone an earlier section already shows.
    private var sections: (nearby: [PlayerSummary], playedWith: [PlayerSummary], everyone: [PlayerSummary]) {
        let nearbyRows = nearby.filter(shows)
        var shown = Set(nearbyRows.map(\.id))
        let playedRows = playedWith.map(\.player).filter { shows($0) && !shown.contains($0.id) }
        shown.formUnion(playedRows.map(\.id))
        let rest = (isSearching ? searchResults : everyone).filter { shows($0) && !shown.contains($0.id) }
        return (nearbyRows, playedRows, rest)
    }

    var body: some View {
        let sections = sections
        NavigationStack {
            List {
                Section {
                    Button {
                        isAddingGuest = true
                    } label: {
                        Label("Add a Guest", systemImage: "person.badge.plus")
                            .foregroundStyle(.kedroRed)
                            .frame(minHeight: 44)
                    }
                    .disabled(room == 0)
                } footer: {
                    Text(room == 0 ? "The table's full at \(GameConfig.seatRange.upperBound)." : "No app needed for guests. Someone at the table reports for them.")
                }
                if !sections.nearby.isEmpty {
                    Section("Nearby") { rows(sections.nearby) }
                }
                if !sections.playedWith.isEmpty {
                    Section("Played With") { rows(sections.playedWith) }
                }
                if !sections.everyone.isEmpty {
                    Section(isSearching ? "On Kedro" : "Everyone") {
                        rows(sections.everyone)
                        if !isSearching, nextPage != nil {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .task { await loadPage() }
                        }
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                } else if sections.nearby.isEmpty, sections.playedWith.isEmpty, sections.everyone.isEmpty, !needle.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name or @handle")
            .navigationTitle("Add Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)") {
                        let picks = selected.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
                        Task {
                            for player in picks { await model.add(player) }
                            dismiss()
                        }
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task { await load() }
            .task { await watchNearby() }
            .task(id: needle) { await search() }
            .sheet(isPresented: $isAddingGuest) {
                GuestSheet(model: model) { dismiss() }
            }
        }
    }

    private func rows(_ players: [PlayerSummary]) -> some View {
        ForEach(players) { player in
            let isOn = selected[player.id] != nil
            Button {
                if isOn { selected[player.id] = nil } else if selected.count < room { selected[player.id] = player }
            } label: {
                PlayerRow(player: player, caption: PlayerRow.playedCaption(model.playedTogether[player.id]), isSelected: isOn, showsSelection: true)
            }
            .buttonStyle(.plain)
            .disabled(!isOn && selected.count >= room)
        }
    }

    private func load() async {
        playedWith = (try? await app.directory.playedWith()) ?? []
        let first = try? await app.directory.everyone(after: nil)
        everyone = first?.players ?? []
        nextPage = first?.next
        isLoading = false
    }

    private func loadPage() async {
        guard let cursor = nextPage, !isLoadingPage else { return }
        isLoadingPage = true
        defer { isLoadingPage = false }
        guard let page = try? await app.directory.everyone(after: cursor) else {
            nextPage = nil
            return
        }
        let known = Set(everyone.map(\.id))
        everyone += page.players.filter { !known.contains($0.id) }
        nextPage = page.next
    }

    private func search() async {
        guard isSearching else {
            searchResults = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        searchResults = (try? await app.directory.search(needle)) ?? []
    }

    /// People at tables this phone can see, closest table first.
    private func watchNearby() async {
        for await tables in app.discovery.nearbyTables() {
            var seen: Set<PlayerID> = []
            nearby = tables.flatMap { [$0.host] + $0.seatedPlayers }.filter { seen.insert($0.id).inserted }
        }
    }
}

/// Add → Guest (design §5.6): a name only. Typing "Sam" suggests "Sam · guest · 2 games with
/// you", so one guest identity builds up history.
struct GuestSheet: View {
    let model: any SeatAdding
    /// After a guest is added (the Add Players sheet closes too).
    var onAdded: () -> Void = {}

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var suggestions: [GuestSuggestion] = []
    @FocusState private var isFocused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isFocused)
                        .onSubmit(addNew)
                } footer: {
                    Text("No app needed. Someone at the table reports for them.")
                }
                let reusable = suggestions.filter { !model.isUnavailable(.guest($0.guestID)) }
                if !reusable.isEmpty {
                    Section("Played before") {
                        ForEach(reusable) { guest in
                            Button {
                                add(Seat(player: .guest(guest.guestID), displayName: guest.name, order: model.seatCount, gamesPlayed: guest.gamesTogether))
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(avatar: nil, name: guest.name, isGuest: true, size: .compact)
                                    Text(guestCaption(guest)).foregroundStyle(.cream)
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add a Guest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addNew).disabled(trimmed.isEmpty)
                }
            }
            .task(id: trimmed) {
                try? await Task.sleep(for: .milliseconds(150))
                suggestions = (try? await app.directory.guestSuggestions(matching: trimmed)) ?? []
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    /// "Sam · guest · 2 games with you"
    private func guestCaption(_ guest: GuestSuggestion) -> String {
        let games = guest.gamesTogether == 1 ? "1 game with you" : "\(guest.gamesTogether) games with you"
        return "\(guest.name) · \(Literal.text("label.guest")) · \(games)"
    }

    private func addNew() {
        guard !trimmed.isEmpty else { return }
        add(Seat(player: .guest(GuestID()), displayName: trimmed, order: model.seatCount, gamesPlayed: 0))
    }

    private func add(_ seat: Seat) {
        Task {
            await model.add(seat)
            dismiss()
            onAdded()
        }
    }
}

#Preview("Add Players") {
    let app = AppModel.preview()
    let model = try? LobbyModel(app: app)
    return Group {
        if let model { AddPlayersSheet(model: model) }
    }
    .previewEnvironment(app)
}

#Preview("Guest") {
    let app = AppModel.preview()
    let model = try? LobbyModel(app: app)
    return Group {
        if let model { GuestSheet(model: model) }
    }
    .previewEnvironment(app)
}
