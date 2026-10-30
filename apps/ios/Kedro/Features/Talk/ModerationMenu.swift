import SwiftUI

/// Mute Their Taunts (this game or always) and Block for one person (design §8.3). Use inside a
/// `Menu` or `.contextMenu`, on a taunt or a profile:
///
/// ```swift
/// Menu("More", systemImage: "ellipsis") { ModerationMenu(person: ref, name: "Ana", gameID: id) }
/// ```
///
/// Block asks first; mutes apply silently (the sender is never told, T-11).
struct ModerationMenu: View {
    let person: PlayerRef
    let name: String
    /// The game for "This Game" mutes; nil on a profile (then only "Always" is offered).
    var gameID: GameID?

    @State private var services = TalkServices.shared
    @State private var isConfirmingBlock = false

    private var seat: SeatID { person.seatID }

    var body: some View {
        let moderation = services.moderation
        let scope = gameID.flatMap { moderation.muteScope(of: seat, in: $0) } ?? (moderation.mutedAlways.contains(seat) ? .always : nil)
        Group {
            if scope != nil {
                Button("Unmute Their Taunts", systemImage: "speaker.wave.2") {
                    moderation.unmute(seat, in: gameID ?? GameID())
                }
            } else if let gameID {
                Menu("Mute Their Taunts", systemImage: "speaker.slash") {
                    ForEach(MuteScope.allCases) { scope in
                        Button(scope.title) { moderation.mute(seat, scope: scope, in: gameID) }
                    }
                }
            } else {
                Button("Mute Their Taunts", systemImage: "speaker.slash") {
                    moderation.mute(seat, scope: .always, in: GameID())
                }
            }
            if moderation.isBlocked(person) {
                Button("Unblock", systemImage: "hand.raised.slash") { services.unblock(person) }
            } else {
                Button("Block", systemImage: "hand.raised", role: .destructive) { isConfirmingBlock = true }
            }
        }
        .confirmationDialog("Block \(name)?", isPresented: $isConfirmingBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { services.block(person) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(name) can't add you to a table, taunt you or send you receipts. They aren't told.")
        }
    }
}

#Preview {
    Menu("Ana") {
        ModerationMenu(person: PreviewData.ana.ref, name: "Ana", gameID: PreviewData.sampleGameID)
    }
    .padding()
    .previewEnvironment()
}
