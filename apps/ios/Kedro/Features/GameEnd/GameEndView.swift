import SwiftUI

/// Game end (design §10, mockup frame 12): the logo lands on `nightGradient`, the winner (96 pt,
/// gold ring) and the winner line picked by how they won, final standings with knock records and
/// rating changes, highlights, debuts, badges and Hall of Shame inductions, then Run It Back, Send
/// a Receipt, Share Results and Done.
///
/// Ratings, badges and Hall of Shame come from Stats through `\.tableInsights`; with nothing
/// installed those sections don't appear.
struct GameEndView: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @Environment(\.tableInsights) private var tableInsights
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dismiss) private var dismiss
    @State private var insights = GameEndInsights.empty
    @State private var hasLanded = false
    @State private var isConfirmingRematch = false
    @State private var isStartingRematch = false
    @State private var isComposingReceipt = false
    @State private var shareImage: Image?

    var body: some View {
        let state = session.state
        let summary = GameEndSummary(state)
        let voice = app.houseVoice(for: state)
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero(summary, voice: voice)
                    standingsCard(summary)
                    lines(summary, voice: voice)
                    debuts(voice: voice)
                    highlights(summary)
                    badges(voice: voice)
                    hallOfShame(voice: voice)
                    finishNote(voice: voice)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) { actions(voice: voice) }
            .background { background }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Literal.text("button.done"), action: done)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            insights = await tableInsights.gameEnd(session.state)
        }
        .task {
            shareImage = ShareResultsCard.render(state: session.state)
        }
        .onAppear {
            if reduceMotion {
                hasLanded = true
            } else {
                withAnimation(.easeOut(duration: 0.5)) { hasLanded = true }
            }
        }
        .alert(TableText.text("label.runItBackTitle"), isPresented: $isConfirmingRematch) {
            Button(Literal.text("button.runItBack")) { runItBack() }
            Button(TableText.text("button.cancel"), role: .cancel) {}
        } message: {
            Text(voice.line("G-06", ["n": state.config.plannedRounds]))
        }
        .sheet(isPresented: $isComposingReceipt) {
            NavigationStack { ReceiptComposer(gameID: session.gameID) }
        }
    }

    // MARK: Hero

    private func hero(_ summary: GameEndSummary, voice: Voice) -> some View {
        let state = session.state
        let winners = summary.winners.compactMap(state.seat)
        return VStack(spacing: 10) {
            LogoView(width: 170)
                .scaleEffect(hasLanded || reduceMotion ? 1 : 1.08)
                .opacity(hasLanded ? 1 : 0)
                .padding(.top, 4)
            HStack(spacing: -18) {
                ForEach(winners) { seat in
                    AvatarView(seat: seat, size: .profile, isLeader: true, ring: .winner)
                }
            }
            .padding(.top, 6)
            if let headline = summary.headline {
                Text(headline.render(voice, gameID: state.gameID, round: state.rounds.count))
                    .kedroFont(.display)
                    .foregroundStyle(.gold)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
            }
            if let line = summary.winnerLine {
                Text(line.render(voice, gameID: state.gameID, round: state.rounds.count))
                    .kedroFont(.roast)
                    .foregroundStyle(.silver)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Standings

    private func standingsCard(_ summary: GameEndSummary) -> some View {
        let state = session.state
        let rows = state.standings
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, standing in
                if index > 0 { Divider().overlay(.rule) }
                GameEndRow(standing: standing, record: summary.knockRecords[standing.id], rating: insights.ratings[standing.id])
                    .opacity(hasLanded ? 1 : 0)
                    .offset(y: hasLanded || reduceMotion ? 0 : 12)
                    // Standings fill in from the bottom (design §3.7).
                    .animation(
                        reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.35).delay(0.35 + Double(rows.count - 1 - index) * 0.08),
                        value: hasLanded
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(.surface, in: .rect(cornerRadius: 22))
    }

    @ViewBuilder
    private func lines(_ summary: GameEndSummary, voice: Voice) -> some View {
        let state = session.state
        let round = state.rounds.count
        VStack(spacing: 6) {
            if let line = summary.lastPlaceLine {
                Text(line.render(voice, gameID: state.gameID, round: round))
            }
            if let seat = summary.lostByOne {
                Text("\(state.name(of: seat)): \(voice.line("W-07"))")
            }
            if let line = summary.bottledLine {
                Text(line.render(voice, gameID: state.gameID, round: round))
            }
        }
        .kedroFont(.roast)
        .foregroundStyle(.silver)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: Ratings debut, highlights, badges, shame

    @ViewBuilder
    private func debuts(voice: Voice) -> some View {
        let state = session.state
        let debuts = state.standings.compactMap { standing in
            insights.ratings[standing.id].flatMap { $0.isDebut ? (standing.seat, $0.after) : nil }
        }
        ForEach(debuts, id: \.0.id) { seat, rating in
            HStack(spacing: 12) {
                AvatarView(seat: seat, size: .medium)
                Text(voice.line("W-05", ["name": seat.displayName, "rating": rating.formatted()]))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.cream)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(.surfaceRaised, in: .rect(cornerRadius: 18))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func highlights(_ summary: GameEndSummary) -> some View {
        let state = session.state
        if !summary.highlights.isEmpty {
            section(TableText.text("label.highlights")) {
                ForEach(Array(summary.highlights.enumerated()), id: \.offset) { _, highlight in
                    Text(GameEndSummary.text(highlight, name: state.name(of:)))
                        .font(.subheadline)
                        .foregroundStyle(.cream)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func badges(voice: Voice) -> some View {
        let state = session.state
        if !insights.badges.isEmpty {
            section(TableText.text("label.badgesEarned")) {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(insights.badges) { badge in
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(LinearGradient(colors: [.kedroRed, .kedroRedDeep], startPoint: .top, endPoint: .bottom))
                                    Circle().strokeBorder(.silver.opacity(0.5), lineWidth: 2)
                                    KMark(height: 18)
                                }
                                .frame(width: 52, height: 52)
                                .accessibilityHidden(true)
                                Text(badge.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.cream)
                                Text(state.name(of: badge.seat))
                                    .font(.caption2)
                                    .foregroundStyle(.silverDim)
                                if let lineID = badge.lineID {
                                    Text(voice.line(lineID, ["name": state.name(of: badge.seat)]))
                                        .font(.caption2)
                                        .foregroundStyle(.silver)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 120)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private func hallOfShame(voice: Voice) -> some View {
        let state = session.state
        ForEach(insights.hallOfShame) { induction in
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.kedroRed)
                    .accessibilityHidden(true)
                Text(voice.line("HS-08", ["category": induction.category, "name": state.name(of: induction.seat)]))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.cream)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(.surfaceRaised, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color.kedroRed.opacity(0.4)) }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func finishNote(voice: Voice) -> some View {
        let state = session.state
        switch state.finishReason {
        case .endedEarly:
            note(TableText.text("label.endedEarly", ["r": state.rounds.count]))
        case .autoFinished:
            note(voice.line("G-02"))
        case .completed, nil:
            EmptyView()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.silverDim)
            .frame(maxWidth: .infinity)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .kedroFont(.label)
                .foregroundStyle(.silver)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.surface, in: .rect(cornerRadius: 18))
    }

    // MARK: Actions

    private func actions(voice: Voice) -> some View {
        let state = session.state
        let isSeated = session.mySeatID != nil
        return VStack(spacing: 10) {
            if isSeated, app.profile != nil {
                Button(Literal.text("button.runItBack")) { isConfirmingRematch = true }
                    .buttonStyle(.kedroPrimary)
                    .disabled(isStartingRematch)
            }
            HStack(spacing: 10) {
                if isSeated {
                    Button(Literal.text("button.sendReceipt")) { isComposingReceipt = true }
                        .buttonStyle(.kedroGlassWide)
                }
                if let shareImage {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview(TableText.text("label.sharePreview", ["word": state.config.tableWord]), image: shareImage)
                    ) {
                        Text(Literal.text("button.shareResults"))
                    }
                    .buttonStyle(.kedroGlassWide)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            LinearGradient(colors: [Color.nightGradientBottom.opacity(0), Color.nightGradientBottom], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var background: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.nightGradient)
            if !reduceTransparency {
                Text("♣")
                    .font(.system(size: 280))
                    .foregroundStyle(Color.cream.opacity(0.03))
                    .offset(x: -50, y: 150)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }

    private func done() {
        if app.liveGame?.gameID == session.gameID {
            app.closeLiveGame()
        } else {
            dismiss()
        }
    }

    private func runItBack() {
        guard let me = session.mySeatID, let plan = Rematch(from: session.state, host: me) else { return }
        isStartingRematch = true
        Task {
            defer { isStartingRematch = false }
            do {
                let next = try await app.createGame(config: plan.config, others: plan.others)
                try await next.start(firstDealer: plan.config.firstDealerSeat)
                app.startLiveGame(next, present: true)
            } catch {
                app.toasts.show(error.localizedDescription)
            }
        }
    }
}

/// One final standings row: rank, avatar, name, "✓2 ✗1 · rating +18 → 1,086" (or the debut, or
/// "guest"), and the final score.
private struct GameEndRow: View {
    let standing: Standing
    var record: GameEndSummary.KnockRecord?
    var rating: RatingChange?

    var body: some View {
        let isWinner = standing.isLeader
        HStack(spacing: 12) {
            Text(standing.rank.label)
                .kedroFont(.headline)
                .foregroundStyle(isWinner ? Color.gold : Color.silver)
                .frame(minWidth: 22)
            AvatarView(seat: standing.seat, size: .compact)
            VStack(alignment: .leading, spacing: 2) {
                Text(standing.seat.displayName)
                    .kedroFont(.headline)
                    .foregroundStyle(.cream)
                    .lineLimit(1)
                caption
            }
            Spacer(minLength: 8)
            ScoreText(value: standing.total, style: .scoreCompact)
                .foregroundStyle(isWinner ? Color.gold : Color.cream)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var parts: [String] {
        var parts: [String] = []
        if standing.seat.isGuest { parts.append(Literal.text("label.guest")) }
        if let record, !record.isEmpty { parts.append(record.text) }
        if let rating, !rating.isDebut, let delta = rating.delta {
            parts.append(TableText.text("label.ratingChange", ["delta": ScoreFormat.signed(delta), "rating": rating.after.formatted()]))
        }
        return parts
    }

    @ViewBuilder
    private var caption: some View {
        if let rating, rating.isDebut {
            Text(([parts.joined(separator: " · ")].filter { !$0.isEmpty } + [TableText.text("label.debut", ["rating": rating.after.formatted()])]).joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.kedroRed)
        } else if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.silverDim)
        }
    }

    private var accessibilityText: String {
        var text = ["\(standing.seat.displayName), \(standing.rank.ordinal) place, \(ScoreFormat.spoken(standing.total)) points"]
        if let record, !record.isEmpty { text.append(record.accessibilityText) }
        if let rating {
            if rating.isDebut {
                text.append("debut rating \(rating.after)")
            } else if let delta = rating.delta {
                text.append("rating \(delta >= 0 ? "up" : "down") \(abs(delta)) to \(rating.after)")
            }
        }
        return text.joined(separator: ", ")
    }
}

#Preview("Sample game") {
    GameEndView(session: PreviewData.sampleSession(throughRound: 8, finished: true))
        .environment(\.tableInsights, TableInsights(gameEnd: { _ in
            GameEndInsights(
                ratings: [
                    PreviewData.noahSeat: RatingChange(before: 1068, after: 1086, isDebut: false),
                    PreviewData.anaSeat: RatingChange(before: 1138, after: 1142, isDebut: false),
                    PreviewData.benSeat: RatingChange(before: nil, after: 986, isDebut: true),
                ],
                badges: [
                    EarnedBadge(seat: PreviewData.noahSeat, name: "Comeback Kid"),
                    EarnedBadge(seat: PreviewData.noahSeat, name: "Ghost Hand"),
                    EarnedBadge(seat: PreviewData.samSeat, name: "Below Zero"),
                ],
                hallOfShame: [ShameInduction(seat: PreviewData.samSeat, category: "Biggest Loss")]
            )
        }))
        .previewEnvironment()
}

#Preview("No insights") {
    GameEndView(session: PreviewData.sampleSession(throughRound: 8, finished: true))
        .previewEnvironment()
}
