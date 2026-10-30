import SwiftUI

/// "Noah's table. Which one's you?" (J-13, mockup frame 20): the unclaimed guest seats with
/// That's me, and Get Kedro at the bottom.
struct ClipSeatPickerView: View {
    @Environment(ClipModel.self) private var model
    let state: GameState

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                seats
                    .padding(.top, 20)
                Text(ClipCopy.notListed(host: model.hostName))
                    .font(.subheadline)
                    .foregroundStyle(.silver)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                Button(Literal.text("button.watch")) {
                    model.isWatching = true
                }
                .buttonStyle(.kedroGlass)
                .padding(.top, 16)
                Text(ClipCopy.footer)
                    .font(.footnote)
                    .foregroundStyle(.silverDim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            ClipGetKedroCard()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            ClipBadge()
                .frame(maxWidth: .infinity, alignment: .leading)
            LogoView(width: 200)
                .padding(.top, 16)
            Text(model.voice.line("J-13", ["host": model.hostName]))
                .kedroFont(.display)
                .foregroundStyle(.cream)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            Text("\(state.config.tableWord) · \(Literal.roundOf(state.progress.currentRound, state.config.plannedRounds))")
                .kedroFont(.label)
                .foregroundStyle(.silver)
                .padding(.top, 6)
        }
    }

    private var seats: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.openGuestSeats.enumerated()), id: \.element.id) { index, seat in
                if index > 0 { Divider().overlay(.rule) }
                HStack(spacing: 12) {
                    AvatarView(seat: seat, size: .compact)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(seat.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.cream)
                        Text(caption(for: seat))
                            .font(.caption)
                            .foregroundStyle(.silverDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button(ClipCopy.thatsMe) {
                        Task { await model.claim(seat) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(index == 0 ? Color.kedroRed : Color.surfaceRaised)
                    .disabled(model.isWorking)
                    .accessibilityLabel("\(ClipCopy.thatsMe): \(seat.displayName)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 56)
            }
        }
        .background(.surface, in: .rect(cornerRadius: 16))
    }

    private func caption(for seat: Seat) -> String {
        let guest = Literal.text("label.guest")
        guard let games = seat.gamesPlayed, games > 0 else { return guest }
        return "\(guest) · \(ClipCopy.gamesWith(games, host: model.hostName))"
    }
}

/// The "App Clip" pill in the top corner (mockup frame 20).
struct ClipBadge: View {
    var body: some View {
        Text(ClipCopy.badge)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.silver)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.surfaceRaised, in: .capsule)
    }
}

#Preview {
    ClipSeatPickerView(state: ClipModel.preview().state ?? PreviewData.sampleState())
        .environment(ClipModel.preview())
        .background(.night)
        .preferredColorScheme(.dark)
}
