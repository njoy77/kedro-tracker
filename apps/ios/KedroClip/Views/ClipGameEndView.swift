import StoreKit
import SwiftUI

/// Game end in the clip (design §5.8): the guest's result and the final standings, plus
/// "Get Kedro to keep this". The claim token is already in the app group, so installing Kedro
/// and signing in claims these games automatically.
struct ClipGameEndView: View {
    @Environment(ClipModel.self) private var model
    let state: GameState

    private var myStanding: Standing? { model.mySeat.flatMap(state.standing(for:)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                LogoView(width: 200)
                    .padding(.top, 24)
                if let myStanding {
                    Text(ClipCopy.result(ordinal: myStanding.rank.ordinal, total: ScoreFormat.string(myStanding.total)))
                        .kedroFont(.display)
                        .foregroundStyle(myStanding.isLeader ? Color.gold : Color.cream)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(state.config.tableWord)
                    .kedroFont(.label)
                    .foregroundStyle(.silver)
                VStack(spacing: 0) {
                    ForEach(state.standings) { standing in
                        ClipStandingRow(standing: standing, isMe: standing.id == model.mySeat, hasRounds: !state.rounds.isEmpty)
                        if standing.id != state.standings.last?.id {
                            Divider().overlay(.rule)
                        }
                    }
                }
                .background(.surface, in: .rect(cornerRadius: 16))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            ClipGetKedroCard(presentsAutomatically: model.mySeat != nil)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }
}

/// "Get Kedro to keep this" with the App Store overlay (`.appStoreOverlay`, design §15).
struct ClipGetKedroCard: View {
    /// Raise the overlay as soon as the card appears (game end, for a seated guest).
    var presentsAutomatically = false

    @State private var showsOverlay = false

    var body: some View {
        HStack(spacing: 12) {
            KMark(height: 22)
                .frame(width: 44, height: 44)
                .background(Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0E / 255), in: .rect(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.rule) }
            VStack(alignment: .leading, spacing: 2) {
                Text(ClipCopy.getKedro)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cream)
                Text(ClipCopy.getKedroSubline)
                    .font(.caption)
                    .foregroundStyle(.silverDim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(ClipCopy.get) { showsOverlay = true }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.kedroRed)
                .accessibilityLabel(ClipCopy.getKedro)
        }
        .padding(12)
        .background(.surfaceRaised, in: .rect(cornerRadius: 18))
        .appStoreOverlay(isPresented: $showsOverlay) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
        .task {
            guard presentsAutomatically else { return }
            try? await Task.sleep(for: .seconds(1.5))
            showsOverlay = true
        }
    }
}

#Preview("Game end, as Sam") {
    ClipGameEndView(state: PreviewData.sampleState(throughRound: 8, finished: true))
        .environment(ClipModel.preview(seated: true, throughRound: 8, finished: true))
        .background(.night)
        .preferredColorScheme(.dark)
}
