import SwiftUI

/// Add → Played With (design §5.6): everyone you've played with, most recent first. Pick several,
/// then Add. Adding is the host vouching: they're seated without Ask to Sit.
struct PlayedWithSheet: View {
    let model: LobbyModel

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var people: [PlayedWith] = []
    @State private var selected: Set<PlayerID> = []
    @State private var isLoading = true
    @State private var filter = ""

    private var room: Int { GameConfig.seatRange.upperBound - model.seats.count }

    private var visible: [PlayedWith] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return people.filter { person in
            !model.isSeated(person.player.ref)
                && (needle.isEmpty || person.player.displayName.lowercased().contains(needle) || person.player.handle.rawValue.contains(needle))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // TODO(networking): "people nearby pre-checked at the top" needs nearby people
                // (not just tables) from TableDiscovery.
                ForEach(visible) { person in
                    let isOn = selected.contains(person.id)
                    Button {
                        if isOn { selected.remove(person.id) } else if selected.count < room { selected.insert(person.id) }
                    } label: {
                        PlayerRow(player: person.player, caption: PlayerRow.playedCaption(person.gamesTogether), isSelected: isOn, showsSelection: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isOn && selected.count >= room)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                } else if people.isEmpty {
                    ContentUnavailableView("Nobody Yet", systemImage: "person.2", description: Text("People you finish a game with show up here."))
                } else if visible.isEmpty {
                    ContentUnavailableView.search(text: filter)
                }
            }
            .searchable(text: $filter, prompt: "Name or @handle")
            .navigationTitle("Played With")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)") {
                        let picks = people.filter { selected.contains($0.id) }.map(\.player)
                        Task {
                            for player in picks { await model.add(player) }
                            dismiss()
                        }
                    }
                    .disabled(selected.isEmpty)
                }
            }
            .task {
                people = (try? await app.directory.playedWith()) ?? []
                isLoading = false
            }
        }
    }
}

/// Add → Search Kedro (design §5.6): any signed-up player by name or @handle, with "Played 3
/// together" or "Never played". Tap to seat them.
struct SearchKedroSheet: View {
    let model: LobbyModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlayerSearchList(
                caption: { player in PlayerRow.playedCaption(model.playedTogether[player.id]) },
                isExcluded: { model.isSeated($0.ref) },
                placement: .navigationBarDrawer(displayMode: .always)
            ) { player in
                Task {
                    await model.add(player)
                    dismiss()
                }
            }
            .navigationTitle("Search Kedro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Add → Guest (design §5.6): a name only. Typing "Sam" suggests "Sam · guest · 2 games with
/// you", so one guest identity builds up history.
struct GuestSheet: View {
    let model: LobbyModel

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
                let reusable = suggestions.filter { !model.isSeated(.guest($0.guestID)) }
                if !reusable.isEmpty {
                    Section("Played before") {
                        ForEach(reusable) { guest in
                            Button {
                                add(Seat(player: .guest(guest.guestID), displayName: guest.name, order: model.seats.count, gamesPlayed: guest.gamesTogether))
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
        add(Seat(player: .guest(GuestID()), displayName: trimmed, order: model.seats.count, gamesPlayed: 0))
    }

    private func add(_ seat: Seat) {
        Task {
            await model.add(seat)
            dismiss()
        }
    }
}

#Preview("Played With") {
    let app = AppModel.preview()
    let model = try? LobbyModel(app: app)
    return Group {
        if let model { PlayedWithSheet(model: model) }
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
