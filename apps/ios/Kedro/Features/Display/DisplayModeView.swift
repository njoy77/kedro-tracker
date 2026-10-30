import SwiftUI

/// Table display mode (design §6.3, mockup frame 21): a phone or iPad propped up in the middle of
/// the table as a shared scoreboard. Left third: the full logo, the round, who deals and the last
/// round. Right two-thirds: big standings and the banter line. Taunts and live knocks cross the top,
/// larger, for 5 s.
///
/// Read-only, so nobody across the table taps it by accident: Record Round appears only after a
/// long-press unlock (with a menu path for people who can't long-press). Forced dark; the screen
/// stays awake; brightness is left alone.
struct DisplayModeView: View {
    let session: GameSession
    @Binding var banner: TableBanner?
    var onRecord: (() -> Void)?
    var onExit: (() -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isUnlocked = false
    @State private var unlocks = 0

    /// How long a banner and the unlock last.
    static let bannerDuration: Duration = .seconds(5)
    static let unlockDuration: Duration = .seconds(10)

    init(session: GameSession) {
        self.init(session: session, banner: .constant(nil))
    }

    init(session: GameSession, banner: Binding<TableBanner?>, onRecord: (() -> Void)? = nil, onExit: (() -> Void)? = nil) {
        self.session = session
        _banner = banner
        self.onRecord = onRecord
        self.onExit = onExit
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            let layout = isLandscape ? AnyLayout(HStackLayout(alignment: .top, spacing: 32)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
            layout {
                summaryColumn(isLandscape: isLandscape)
                    .frame(width: isLandscape ? max(240, proxy.size.width / 3) : nil)
                standingsColumn
            }
            .padding(.horizontal, isLandscape ? 40 : 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background { background }
        .overlay(alignment: .top) { bannerView }
        .overlay(alignment: .bottomTrailing) { controls }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .keepsScreenAwake()
        .sensoryFeedback(.impact(weight: .medium), trigger: unlocks)
        .task(id: banner?.id) {
            guard banner != nil else { return }
            try? await Task.sleep(for: Self.bannerDuration)
            guard !Task.isCancelled else { return }
            withAnimation { banner = nil }
        }
        .task(id: unlocks) {
            guard isUnlocked else { return }
            try? await Task.sleep(for: Self.unlockDuration)
            guard !Task.isCancelled else { return }
            withAnimation { isUnlocked = false }
        }
    }

    private var state: GameState { session.state }

    // MARK: Left: logo, round, last round

    private func summaryColumn(isLandscape: Bool) -> some View {
        let voice = app.houseVoice(for: state)
        return VStack(alignment: .leading, spacing: 10) {
            LogoView(width: isLandscape ? 210 : 170)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TableText.text("label.round", ["r": state.progress.currentRound]))
                    .kedroFont(.display)
                    .foregroundStyle(.cream)
                Text(TableText.text("label.ofTotal", ["total": state.config.plannedRounds]))
                    .kedroFont(.display)
                    .foregroundStyle(.silver)
            }
            .accessibilityElement(children: .combine)
            Text(metadata)
                .kedroFont(.label)
                .foregroundStyle(.silver)
            if isLandscape { Spacer(minLength: 12) }
            LastRoundCard(state: state, voice: voice, compact: true)
        }
        .frame(maxHeight: isLandscape ? .infinity : nil, alignment: .topLeading)
    }

    /// "NOAH DEALS · SAM KNOCKED · LAST TURNS"
    private var metadata: String {
        var parts: [String] = []
        if let dealer = state.currentDealer {
            parts.append(Literal.deals(word: state.config.tableWord, dealer: state.name(of: dealer)))
        }
        if let mark = state.liveKnock {
            parts.append(TableText.text("label.lastTurns", ["name": state.name(of: mark.knocker)]))
        }
        return parts.joined(separator: " · ").uppercased()
    }

    // MARK: Right: standings

    private var standingsColumn: some View {
        GeometryReader { proxy in
            let count = max(state.standings.count, 1)
            let banterSpace: CGFloat = 44
            let rowHeight = min(64, max(34, (proxy.size.height - banterSpace) / CGFloat(count)))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(state.standings) { standing in
                    DisplayStandingRow(standing: standing, height: rowHeight, showsLeader: !state.rounds.isEmpty)
                }
                if let banter = TableVoice.banter(for: state) {
                    Text(banter.render(app.houseVoice(for: state), gameID: state.gameID, round: state.rounds.count))
                        .kedroFont(.roast)
                        .foregroundStyle(.silver)
                        .padding(.top, 10)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.45, bounce: 0.15), value: state.standings.map(\.id))
        }
    }

    // MARK: Banner, controls, background

    @ViewBuilder
    private var bannerView: some View {
        if let banner {
            HStack(spacing: 14) {
                if let seat = banner.seat {
                    AvatarView(seat: seat, size: .medium)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(banner.eyebrow)
                        .kedroFont(.label)
                        .foregroundStyle(banner.kind == .liveKnock ? Color.kedroRed : Color.silver)
                    Text(banner.message)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.cream)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.surfaceRaised, in: .rect(cornerRadius: 22))
            .overlay {
                if banner.kind == .liveKnock {
                    RoundedRectangle(cornerRadius: 22).strokeBorder(Color.kedroRed.opacity(0.6), lineWidth: 1.5)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            if let onRecord, state.status == .active {
                if isUnlocked {
                    Button(state.isAwaitingFinish ? Literal.text("button.finishGame") : recordTitle) {
                        isUnlocked = false
                        onRecord()
                    }
                    .buttonStyle(.kedroPrimary)
                    .frame(maxWidth: 260)
                    .transition(.opacity)
                } else {
                    Label(TableText.text("label.holdToRecord"), systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.silverDim)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                        .onLongPressGesture(minimumDuration: 0.8) { unlock() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { unlock() }
                }
            }
            Menu {
                if let onRecord, state.status == .active {
                    Button(recordTitle, systemImage: "number") { onRecord() }
                }
                if let onExit {
                    Button(TableText.text("button.exitTableDisplay"), systemImage: "rectangle.portrait") { onExit() }
                }
            } label: {
                Label(TableText.text("button.more"), systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.silver)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(16)
        .animation(.smooth(duration: 0.25), value: isUnlocked)
    }

    private var recordTitle: String {
        state.config.scoringMode == .selfReport ? Literal.text("button.reportHand") : Literal.recordRound(state.nextRoundNumber)
    }

    private func unlock() {
        unlocks += 1
        withAnimation { isUnlocked = true }
    }

    private var background: some View {
        ZStack {
            Rectangle().fill(.nightGradient)
            if !reduceTransparency {
                Text("♥")
                    .font(.system(size: 420))
                    .foregroundStyle(Color.kedroRed.opacity(0.035))
                    .offset(x: 120, y: -80)
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }
}

/// A big standings row for display mode: rank, avatar, name with LEADING, score.
private struct DisplayStandingRow: View {
    let standing: Standing
    let height: CGFloat
    var showsLeader = true

    var body: some View {
        let isLeading = showsLeader && standing.isLeader
        let scale = height / 64
        HStack(spacing: 14 * scale) {
            Text(standing.rank.label)
                .font(.custom(KedroTextStyle.bebas, size: 30 * scale))
                .foregroundStyle(isLeading ? Color.gold : Color.silver)
                .frame(minWidth: 30 * scale)
            AvatarView(seat: standing.seat, size: height >= 56 ? .standings : .compact, isLeader: isLeading, isDealer: standing.isDealer, ring: isLeading ? .winner : .none)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(standing.seat.displayName.uppercased())
                    .font(.custom(KedroTextStyle.bebas, size: 34 * scale))
                    .foregroundStyle(.cream)
                    .lineLimit(1)
                if isLeading {
                    Text(Literal.text("label.leading"))
                        .font(.custom(KedroTextStyle.bebas, size: 15 * scale))
                        .foregroundStyle(.gold)
                }
            }
            Spacer(minLength: 8)
            Text(ScoreFormat.string(standing.total))
                .font(.custom(KedroTextStyle.bebas, size: 52 * scale).monospacedDigit())
                .foregroundStyle(isLeading ? Color.gold : Color.cream)
                .contentTransition(.numericText(value: Double(standing.total)))
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(standing.seat.displayName), \(standing.rank.ordinal) place, \(ScoreFormat.spoken(standing.total)) points" + (isLeading ? ", leading" : "") + (standing.isDealer ? ", dealer" : ""))
    }
}

#Preview("Landscape", traits: .landscapeLeft) {
    DisplayModeView(
        session: PreviewData.sampleSession(throughRound: 5, liveKnock: true),
        banner: .constant(TableBanner(id: UUID(), kind: .taunt, seat: PreviewData.sampleSeats[1], eyebrow: "Ana → Sam", message: "Knocking on that? Brave.")),
        onRecord: {},
        onExit: {}
    )
    .previewEnvironment()
}

#Preview("8 players", traits: .landscapeLeft) {
    DisplayModeView(session: TablePreviews.eightPlayerSession)
        .previewEnvironment()
}
