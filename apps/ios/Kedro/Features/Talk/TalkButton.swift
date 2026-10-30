import SwiftUI

/// The Table's Talk button (the 💬 that flanks Record Round, mockup frame 6). Opens the Talk
/// sheet aimed at whoever just did something roastable, otherwise the table.
struct TalkButton: View {
    let session: GameSession

    @State private var target: TauntTarget?

    var body: some View {
        Button {
            target = .suggested(for: session.state, me: session.mySeatID)
        } label: {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .frame(width: 28)
        }
        .buttonStyle(.kedroGlass)
        .accessibilityLabel("Talk")
        .disabled(!session.state.status.isLive)
        .sheet(item: $target) { target in
            TalkSheet(session: session, target: target)
        }
    }
}

extension TauntTarget: Identifiable {
    var id: String {
        switch self {
        case .table: "table"
        case .seat(let seat): seat.rawValue
        }
    }
}

#Preview {
    TalkButton(session: PreviewData.sampleSession(liveKnock: true))
        .padding()
        .background(.night)
        .previewEnvironment()
}
