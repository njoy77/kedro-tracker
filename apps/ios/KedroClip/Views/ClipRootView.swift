import SwiftUI

/// The clip's one screen, by phase: waiting for a link, connecting, offline (F-04), an expired
/// code, then the seat picker ("Which one's you?"), the live Table and the game end.
struct ClipRootView: View {
    @Environment(ClipModel.self) private var model

    var body: some View {
        ZStack {
            Rectangle().fill(.nightGradient).ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .animation(.smooth, value: model.phase)
        .alert(
            "Kedro",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(Literal.text("button.done"), role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .waitingForInvite:
            ClipMessageView(message: ClipCopy.scanPrompt)
        case .connecting:
            ProgressView()
                .controlSize(.large)
                .tint(.cream)
        case .offline:
            ClipMessageView(message: model.voice.line("F-04", ["host": model.hostName]), retry: true)
        case .expired:
            ClipMessageView(message: ClipCopy.expired(host: model.hostName))
        case .table:
            if let state = model.state {
                if state.status == .finished || state.status == .abandoned {
                    ClipGameEndView(state: state)
                } else if model.mySeat == nil, !model.isWatching {
                    ClipSeatPickerView(state: state)
                } else {
                    ClipTableView(state: state)
                }
            }
        }
    }
}

/// The logo and one line, with Try Again when it makes sense.
struct ClipMessageView: View {
    @Environment(ClipModel.self) private var model
    let message: String
    var retry = false

    var body: some View {
        VStack(spacing: 24) {
            LogoView(width: 200)
            Text(message)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.cream)
                .multilineTextAlignment(.center)
            if retry {
                Button(ClipCopy.tryAgain) {
                    Task { await model.connect() }
                }
                .buttonStyle(.kedroGlass)
            }
        }
        .padding(32)
    }
}

#Preview("Seat picker") {
    ClipRootView()
        .environment(ClipModel.preview())
}

#Preview("Table") {
    ClipRootView()
        .environment(ClipModel.preview(seated: true, throughRound: 5))
}

#Preview("Message") {
    ClipMessageView(message: ClipCopy.scanPrompt, retry: true)
        .environment(ClipModel.preview())
        .background(.night)
}
