import SwiftUI

extension View {
    /// Runs the trash talk for a live game on this phone: taunt toasts (design §8.1) and the sound
    /// pack (§3.8), while this view is on screen.
    ///
    /// Apply it to the Table (and display mode), which also presents the feed when a taunt toast
    /// is tapped. Apply it with `presentsFeed: false` where the minimized game lives (the tab
    /// view) so toasts and sounds keep coming while the Table is minimized; it never runs twice.
    func trashTalk(for session: GameSession?, presentsFeed: Bool = true) -> some View {
        modifier(TrashTalkModifier(session: session, presentsFeed: presentsFeed))
    }
}

private struct TrashTalkModifier: ViewModifier {
    let session: GameSession?
    let presentsFeed: Bool

    @Environment(AppModel.self) private var app
    @Environment(AuthStore.self) private var auth: AuthStore?
    @State private var services = TalkServices.shared

    func body(content: Content) -> some View {
        content
            .task(id: session?.gameID) {
                if let auth { services.configure(auth: auth) }
                guard let session else { return }
                await services.hold(session, app: app)
            }
            .sheet(isPresented: feedBinding) {
                if let session {
                    NavigationStack {
                        FeedView(session: session)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { services.feedRequest = nil }
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                    .toastHost(app.toasts)
                }
            }
    }

    private var feedBinding: Binding<Bool> {
        Binding {
            presentsFeed && session != nil && services.feedRequest == session?.gameID
        } set: { isPresented in
            if !isPresented { services.feedRequest = nil }
        }
    }
}

#Preview {
    @Previewable @State var app = AppModel.preview(liveGame: true)
    Text("The Table")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.night)
        .trashTalk(for: app.liveGame)
        .previewEnvironment(app)
}
