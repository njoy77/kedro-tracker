import SwiftUI

/// The game feed (design §8.4): round results, live knocks, taunts, reactions, receipts and
/// every "On the record" change, oldest first, opening at the newest.
///
/// It's part of the game's permanent record once finished, except what this phone hides:
/// reported, muted and blocked content, taunts over the rate limits, and custom taunts when
/// custom taunts are off here. Long-press a taunt to report it, mute or block the sender.
///
/// No navigation stack of its own: the History sheet's Feed tab embeds it, and the taunt toast
/// presents it in a sheet (`.trashTalk(for:)`).
struct FeedView: View {
    let session: GameSession

    @Environment(AppPreferences.self) private var prefs
    @State private var services = TalkServices.shared

    private var state: GameState { session.state }

    private var entries: [FeedEntry] {
        FeedFilter.entries(
            in: state,
            visibleTaunts: Set(services.visibleTaunts(in: state, preferences: prefs).map(\.tauntId)),
            hides: { services.moderation.hidesReceipt(from: $0, in: state.gameID) }
        )
    }

    var body: some View {
        let entries = entries
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "text.bubble", description: Text("Rounds, knocks and taunts show up here."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            FeedRow(entry: entry, session: session)
                            Divider().overlay(.rule).padding(.leading, 68)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
            }
        }
        .background(.surface)
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Which feed entries this phone shows. Pure, so the rules are tested.
nonisolated enum FeedFilter {
    /// - Parameters:
    ///   - visibleTaunts: the taunts this phone shows (moderation, custom setting, rate limits).
    ///   - hides: whether a person's receipts and reactions are hidden (blocked or muted).
    static func entries(in state: GameState, visibleTaunts: Set<UUID>, hides: (SeatID) -> Bool) -> [FeedEntry] {
        state.feed.filter { entry in
            switch entry.kind {
            case .taunt(let taunt): visibleTaunts.contains(taunt.tauntId)
            case .receipt(let receipt): !hides(receipt.from)
            case .reaction(_, let seat, _): !hides(seat)
            case .roundSaved, .liveKnock, .record: true
            }
        }
    }
}

private struct FeedRow: View {
    let entry: FeedEntry
    let session: GameSession

    @Environment(AppModel.self) private var app
    @Environment(AppPreferences.self) private var prefs
    @State private var services = TalkServices.shared
    @State private var blockRequest: BlockRequest?

    private var state: GameState { session.state }
    /// The feed is a shared game surface (house voice); taunts and receipts are personal, so
    /// they render in the viewer's level.
    private var houseVoice: Voice { app.houseVoice(for: state) }
    private var myLevel: LanguageLevel { prefs.effectiveLanguageLevel }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            leading
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(eyebrow)
                        .font(.caption)
                        .foregroundStyle(isLiveKnock ? Color.kedroRed : Color.silver)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(entry.at, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.silverDim)
                        .monospacedDigit()
                }
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.cream)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .contextMenu { menu }
        .blockConfirmation($blockRequest)
    }

    // MARK: Content

    private var isLiveKnock: Bool {
        if case .liveKnock = entry.kind { true } else { false }
    }

    @ViewBuilder
    private var leading: some View {
        switch entry.kind {
        case .taunt(let taunt):
            avatar(for: taunt.from, fallback: taunt.fromName)
        case .reaction(_, let seat, _):
            avatar(for: seat, fallback: state.name(of: seat))
        case .receipt(let receipt):
            avatar(for: receipt.from, fallback: state.name(of: receipt.from))
        case .liveKnock(let knock):
            avatar(for: knock.knocker, fallback: state.name(of: knock.knocker))
        case .roundSaved(let number):
            symbol("suit.spade.fill", label: "Round \(number)")
        case .record:
            symbol("pencil", label: "On the record")
        }
    }

    @ViewBuilder
    private func avatar(for seat: SeatID?, fallback name: String) -> some View {
        if let seat = seat.flatMap({ state.seat($0) }) {
            AvatarView(seat: seat, size: .compact)
        } else {
            AvatarView(avatar: nil, name: name, isGuest: true, size: .compact)
        }
    }

    private func symbol(_ name: String, label: String) -> some View {
        Circle()
            .fill(.surfaceRaised)
            .frame(width: AvatarView.Size.compact.rawValue, height: AvatarView.Size.compact.rawValue)
            .overlay { Image(systemName: name).font(.footnote).foregroundStyle(.silver) }
            .accessibilityLabel(label)
    }

    /// Literal line above the message.
    private var eyebrow: String {
        switch entry.kind {
        case .roundSaved(let number): "Round \(number)"
        case .liveKnock: "Live knock"
        case .taunt(let taunt): TauntRendering.eyebrow(for: taunt, in: state)
        case .reaction(let round, let seat, _): "\(state.name(of: seat)) · Round \(round)"
        case .receipt(let receipt): "\(state.name(of: receipt.from)) → \(state.name(of: receipt.to)) · receipt"
        case .record: "On the record"
        }
    }

    private var message: String? {
        switch entry.kind {
        case .roundSaved(let number):
            guard let record = state.round(number), let hand = record.round.hands[record.knocker] else { return nil }
            let fact = Literal.fact(round: number, knocker: state.name(of: record.knocker), hand: hand)
            guard let outcome = record.outcome else { return fact }
            return fact + " " + Literal.verdict(outcome, hand: hand)
        case .liveKnock(let knock):
            return houseVoice.line("K-21", ["knocker": state.name(of: knock.knocker)])
        case .taunt(let taunt):
            return TauntRendering.text(taunt.content, level: myLevel, filter: services.filter)
        case .reaction(_, _, let reaction):
            return reaction.emoji
        case .receipt(let receipt):
            return Receipts.option(receipt.receiptKey, in: state, from: receipt.from, to: receipt.to)?.line(level: myLevel)
        case .record(let audit):
            return audit.summary
        }
    }

    // MARK: Safeguards

    /// Report (custom taunts), Mute Their Taunts and Block, for anything someone else sent.
    @ViewBuilder
    private var menu: some View {
        if case .taunt(let taunt) = entry.kind, let sender = taunt.from, sender != session.mySeatID,
           let person = state.seat(sender) {
            if taunt.content.isCustom {
                Menu("Report", systemImage: "flag") {
                    ForEach(ReportReason.allCases) { reason in
                        Button(reason.title) { report(taunt, reason: reason) }
                    }
                }
            }
            ModerationMenu(person: person.player, name: person.displayName, gameID: state.gameID) { blockRequest = $0 }
        }
    }

    private func report(_ taunt: TauntRecord, reason: ReportReason) {
        services.report(taunt, reason: reason)
        app.toasts.show(Voice(level: myLevel).line("T-13"))
    }
}

#Preview("Live game") {
    NavigationStack {
        FeedView(session: PreviewData.sampleSession(liveKnock: true))
    }
    .previewEnvironment()
}

#Preview("Finished") {
    NavigationStack {
        FeedView(session: PreviewData.sampleSession(throughRound: 8, finished: true))
    }
    .previewEnvironment()
}
