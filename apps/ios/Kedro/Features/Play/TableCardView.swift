import SwiftUI

/// What the Table card shows (design §5.3, §5.5): a table seen nearby, opened from a link, or a
/// seat the host saved for you.
nonisolated struct TableCardContent: Hashable, Sendable, Identifiable {
    var id: GameID
    var hostName: String
    var hostAvatar: Avatar?
    var tableWord: String
    /// Meters (UWB), when known.
    var distance: Double?
    var seated: [PlayerSummary]
    var guestCount: Int
    var isPlayedWith: Bool
    var roundsPlayed: Int
    /// The host added you (Played With or Search): Sit Down seats you, no asking (§5.5).
    var hasSavedSeat: Bool

    init(table: NearbyTable, hasSavedSeat: Bool = false) {
        id = table.id
        hostName = table.host.displayName
        hostAvatar = table.host.avatar
        tableWord = table.tableWord
        distance = table.distance
        seated = table.seatedPlayers
        guestCount = table.guestCount
        isPlayedWith = table.isPlayedWith
        roundsPlayed = table.roundsPlayed
        self.hasSavedSeat = hasSavedSeat
    }

    /// A table known from its stored log (a saved seat that has synced) or just from a link.
    init(gameID: GameID, state: GameState?, link: TableInviteLink?, me: PlayerRef?) {
        id = gameID
        let host = state?.hostSeat.flatMap { state?.seat($0) }
        hostName = host?.displayName ?? link?.hostName ?? "Someone"
        hostAvatar = host?.avatar
        tableWord = state?.config.tableWord ?? link?.tableWord ?? "A Table"
        distance = nil
        let others = (state?.seats ?? []).filter { $0.player != me }
        seated = others.compactMap { seat in
            guard case .player(let id) = seat.player, let handle = seat.handle else { return nil }
            return PlayerSummary(id: id, displayName: seat.displayName, handle: handle, avatar: seat.avatar ?? .curated(.spade), titleID: seat.titleID, gamesPlayed: seat.gamesPlayed)
        }
        guestCount = others.filter(\.isGuest).count
        let saved = me.map { state?.seat(for: $0) != nil } ?? false
        hasSavedSeat = saved || link?.kind == .savedSeat
        // A link someone handed you (QR, AirDrop) is the host vouching, like a saved seat.
        isPlayedWith = hasSavedSeat || link?.kind == .table
        roundsPlayed = state?.rounds.count ?? 0
    }

    var action: SitDownAction {
        SitDownAction.action(isPlayedWith: isPlayedWith, hasSavedSeat: hasSavedSeat, seatsLocked: roundsPlayed > 0)
    }

    /// "MAYA'S TABLE" (real casing; Bebas uppercases it).
    var title: String { "\(hostName)'s Table" }

    /// "COLD DECK · AT YOUR TABLE · 0.6 M"
    var locationLine: String {
        var parts = [tableWord]
        if let distance {
            parts.append(distance < NearbyTable.atYourTableDistance ? "At your table" : "Nearby")
            parts.append(distance.formatted(.number.precision(.fractionLength(1))) + " m")
        } else if hasSavedSeat {
            parts.append("Seat saved")
        } else {
            parts.append("Nearby")
        }
        if roundsPlayed > 0 { parts.append("Round \(roundsPlayed + 1)") }
        return parts.joined(separator: " · ")
    }

    /// "Maya, Theo, Priya + 1 guest"
    var seatedLine: String {
        var names = seated.map(\.displayName)
        if names.isEmpty { names = [hostName] }
        var line = names.formatted(.list(type: .and, width: .narrow))
        if guestCount > 0 { line += " + \(guestCount) guest" + (guestCount == 1 ? "" : "s") }
        return line
    }
}

/// The Table card that rises over Play when a table is nearby (design §5.3, mockup frame 4).
struct TableCardView: View {
    let content: TableCardContent
    /// Stakes for you at this table (J-01, J-05).
    var stakes: [StakesLine]
    /// Your finished games, for the 5-step meter (shown under 5).
    var myGamesPlayed: Int
    var otherTablesCount: Int
    var isWaitingForHost = false
    var isWorking = false
    var onAction: () -> Void
    var onShowOthers: () -> Void
    var onDismiss: () -> Void

    @Environment(AppModel.self) private var app
    @AccessibilityFocusState private var actionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(.rule)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title)
                        .kedroFont(.display)
                        .foregroundStyle(.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(content.locationLine).kedroFont(.label).foregroundStyle(.silver)
                }
                Spacer()
                KMark(height: 30)
                Button("Not Now", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.silver)
                    .frame(width: 44, height: 44)
            }
            .accessibilityElement(children: .contain)

            if content.hasSavedSeat {
                Text(app.voice.line("N-01", ["host": content.hostName, "word": content.tableWord]))
                    .font(.subheadline)
                    .foregroundStyle(.cream)
            }

            HStack(spacing: 10) {
                HStack(spacing: -6) {
                    ForEach(content.seated.prefix(5)) { player in
                        AvatarView(player: player, size: .compact)
                            .overlay { Circle().stroke(.surfaceRaised, lineWidth: 2) }
                    }
                    ForEach(0..<min(content.guestCount, 3), id: \.self) { _ in
                        AvatarView(avatar: nil, name: "Guest", isGuest: true, size: .compact)
                            .background(.surfaceRaised, in: .circle)
                    }
                }
                .accessibilityHidden(true)
                Text(content.seatedLine)
                    .font(.subheadline)
                    .foregroundStyle(.silver)
                    .lineLimit(2)
            }

            if !stakes.isEmpty && stakes != [.nothing] || myGamesPlayed < 5 {
                VStack(alignment: .leading, spacing: 6) {
                    if myGamesPlayed < 5 { ProgressMeter(value: myGamesPlayed) }
                    ForEach(stakes.filter { $0 != .nothing }, id: \.self) { line in
                        Text(line.text(app.voice)).font(.subheadline).foregroundStyle(.cream)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.surface, in: .rect(cornerRadius: 14))
            }

            if isWaitingForHost {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Asked \(content.hostName). Waiting for a yes.")
                        .font(.subheadline)
                        .foregroundStyle(.silver)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                Button(action: onAction) {
                    if isWorking { ProgressView().tint(.white) } else { Text(content.action.title) }
                }
                .buttonStyle(.kedroPrimary)
                .disabled(isWorking)
                .accessibilityFocused($actionFocused)
            }

            if otherTablesCount > 0 {
                Button(app.voice.line("J-16", ["n": otherTablesCount]), action: onShowOthers)
                    .font(.footnote)
                    .foregroundStyle(.silver)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background(.surfaceRaised, in: .rect(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.rule) }
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                if value.translation.height > 80 { onDismiss() }
            }
        )
        .accessibilityAction(named: "Not Now", onDismiss)
        .onAppear {
            // A saved seat lands with Sit Down focused (design §5.5).
            if content.hasSavedSeat { actionFocused = true }
        }
    }
}

#Preview("Table card") {
    let table = NearbyTable(
        id: GameID(), host: PreviewData.maya, tableWord: "Last Call", distance: 0.6,
        seatedPlayers: [PreviewData.maya, PreviewData.theo, PreviewData.priya], guestCount: 1,
        isPlayedWith: true, roundsPlayed: 0
    )
    return VStack {
        Spacer()
        TableCardView(
            content: TableCardContent(table: table), stakes: [.fifthGame], myGamesPlayed: 4,
            otherTablesCount: 2, onAction: {}, onShowOthers: {}, onDismiss: {}
        )
        .padding(8)
    }
    .background(.night)
    .previewEnvironment()
    .preferredColorScheme(.dark)
}

#Preview("Stranger") {
    let table = NearbyTable(
        id: GameID(), host: PreviewData.jo, tableWord: "Dead Hand", distance: nil,
        seatedPlayers: [PreviewData.jo], guestCount: 0, isPlayedWith: false, roundsPlayed: 0
    )
    return VStack {
        Spacer()
        TableCardView(
            content: TableCardContent(table: table), stakes: [.nothing], myGamesPlayed: 12,
            otherTablesCount: 0, onAction: {}, onShowOthers: {}, onDismiss: {}
        )
        .padding(8)
    }
    .background(.night)
    .previewEnvironment()
    .preferredColorScheme(.dark)
}
