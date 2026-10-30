import SwiftUI

/// ⋯ → Add Player on the Table: the Add Players sheet for a game in progress. Whoever's added
/// plays from the next round at the highest total (G-10).
struct LateJoinSheet: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @State private var model: LateJoinModel?

    var body: some View {
        Group {
            if let model {
                AddPlayersSheet(model: model)
                    .task { await model.load() }
            } else {
                ProgressView()
            }
        }
        .task {
            if model == nil { model = LateJoinModel(app: app, session: session) }
        }
    }
}

#Preview {
    let app = AppModel.preview(liveGame: true)
    return Group {
        if let session = app.liveGame { LateJoinSheet(session: session) }
    }
    .previewEnvironment(app)
}
