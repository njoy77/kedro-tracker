import SwiftUI

/// Someone the viewer asked to block, waiting on the confirmation.
struct BlockRequest: Identifiable, Hashable {
    var person: PlayerRef
    var name: String

    var id: PlayerRef { person }
}

/// Mute Their Taunts (this game or always) and Block for one person (design §8.3). Use inside a
/// `Menu` or `.contextMenu`, on a taunt or a profile, and put `.blockConfirmation(_:)` on a view
/// outside the menu (a menu's content is gone by the time a dialog would show):
///
/// ```swift
/// @State private var blockRequest: BlockRequest?
/// Menu("More", systemImage: "ellipsis") {
///     ModerationMenu(person: ref, name: "Ana", gameID: id) { blockRequest = $0 }
/// }
/// .blockConfirmation($blockRequest)
/// ```
///
/// Mutes apply silently (the sender is never told, T-11); Block asks first.
struct ModerationMenu: View {
    let person: PlayerRef
    let name: String
    /// The game for "This Game" mutes; nil on a profile (then only "Always" is offered).
    var gameID: GameID?
    /// Block was chosen: confirm with `.blockConfirmation(_:)`.
    var onBlock: (BlockRequest) -> Void

    @State private var services = TalkServices.shared

    private var seat: SeatID { person.seatID }

    var body: some View {
        let moderation = services.moderation
        let isMuted = gameID.map { moderation.isMuted(seat, in: $0) } ?? moderation.mutedAlways.contains(seat)
        if isMuted {
            Button("Unmute Their Taunts", systemImage: "speaker.wave.2") {
                moderation.unmute(seat, in: gameID)
            }
        } else if let gameID {
            Menu("Mute Their Taunts", systemImage: "speaker.slash") {
                ForEach(MuteScope.allCases) { scope in
                    Button(scope.title) { moderation.mute(seat, scope: scope, in: gameID) }
                }
            }
        } else {
            Button("Mute Their Taunts", systemImage: "speaker.slash") {
                moderation.muteAlways(seat)
            }
        }
        if moderation.isBlocked(person) {
            Button("Unblock", systemImage: "hand.raised.slash") { services.unblock(person) }
        } else {
            Button("Block", systemImage: "hand.raised", role: .destructive) {
                onBlock(BlockRequest(person: person, name: name))
            }
        }
    }
}

extension View {
    /// Confirms a Block chosen from a `ModerationMenu`, then blocks.
    func blockConfirmation(_ request: Binding<BlockRequest?>) -> some View {
        modifier(BlockConfirmation(request: request))
    }
}

private struct BlockConfirmation: ViewModifier {
    @Binding var request: BlockRequest?
    @State private var services = TalkServices.shared

    func body(content: Content) -> some View {
        content.confirmationDialog(
            request.map { "Block \($0.name)?" } ?? "Block",
            isPresented: Binding { request != nil } set: { if !$0 { request = nil } },
            titleVisibility: .visible,
            presenting: request
        ) { request in
            Button("Block", role: .destructive) { services.block(request.person) }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text("\(request.name) can't add you to a table, taunt you or send you receipts. They aren't told.")
        }
    }
}

#Preview {
    @Previewable @State var request: BlockRequest?
    Menu("Ana") {
        ModerationMenu(person: PreviewData.ana.ref, name: "Ana", gameID: PreviewData.sampleGameID) { request = $0 }
    }
    .padding()
    .blockConfirmation($request)
    .previewEnvironment()
}
