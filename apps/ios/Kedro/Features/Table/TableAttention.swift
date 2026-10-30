import SwiftUI

/// Something big enough to cross the table: a live knock or a taunt. On the phone it's a toast;
/// in display mode it's a full-width banner for 5 s (design §6.3).
struct TableBanner: Identifiable, Equatable {
    enum Kind: Equatable { case liveKnock, taunt }

    let id: UUID
    var kind: Kind
    var seat: Seat?
    var eyebrow: String
    var message: String
}

/// Which History tab to open.
enum HistoryTab: Hashable, CaseIterable, Identifiable {
    case scores, record, feed

    var id: Self { self }

    var title: String {
        switch self {
        case .scores: TableText.text("label.scores")
        case .record: TableText.text("label.onTheRecord")
        case .feed: TableText.text("label.feed")
        }
    }
}

extension View {
    /// The Table's attention rules (design §6.5, §7.5, §8.1): turns new feed entries from the
    /// operation log into toasts (or display-mode banners). Live knocks toast every phone with a
    /// heavy haptic and Undo on the marking phone; taunts from other phones toast in this
    /// viewer's level; other people's corrections get H-02. `ToastCenter` already queues
    /// everything while a Round sheet is open.
    func tableAttention(
        _ session: GameSession,
        isDisplayMode: Bool,
        banner: Binding<TableBanner?>,
        openHistory: @escaping (HistoryTab) -> Void
    ) -> some View {
        modifier(TableAttentionModifier(session: session, isDisplayMode: isDisplayMode, banner: banner, openHistory: openHistory))
    }
}

private struct TableAttentionModifier: ViewModifier {
    let session: GameSession
    let isDisplayMode: Bool
    @Binding var banner: TableBanner?
    let openHistory: (HistoryTab) -> Void

    @Environment(AppModel.self) private var app
    @Environment(AppPreferences.self) private var prefs
    @Environment(\.tauntRendering) private var tauntRendering
    @State private var seen: Set<UUID>?
    @State private var heavyHaptics = 0

    /// Older operations (synced in late) don't interrupt anyone; they're in the feed.
    static let freshness: TimeInterval = 120

    func body(content: Content) -> some View {
        content
            .onAppear {
                if seen == nil { seen = Set(session.state.feed.map(\.id)) }
            }
            .onChange(of: session.state.feed.count) { handleNewEntries() }
            .sensoryFeedback(.impact(weight: .heavy), trigger: heavyHaptics)
    }

    private func handleNewEntries() {
        var known = seen ?? []
        let fresh = session.state.feed.filter { known.insert($0.id).inserted }
        seen = known
        for entry in fresh where Date.now.timeIntervalSince(entry.at) < Self.freshness {
            handle(entry)
        }
    }

    private func isMine(_ opID: UUID) -> Bool {
        session.operations.last { $0.opId == opID }?.deviceId == session.identity.deviceID
    }

    private func handle(_ entry: FeedEntry) {
        let state = session.state
        switch entry.kind {
        case .liveKnock(let mark):
            guard state.liveKnock?.opId == mark.opId else { return }
            liveKnock(mark, mine: isMine(entry.opId))
        case .taunt(let taunt):
            guard !taunt.isRetracted, !isMine(entry.opId) else { return }
            self.taunt(taunt)
        case .record(let audit):
            guard !isMine(entry.opId) else { return }
            record(audit)
        case .roundSaved, .reaction, .receipt:
            return
        }
    }

    // MARK: Live knock

    private func liveKnock(_ mark: LiveKnock, mine: Bool) {
        let state = session.state
        let name = state.name(of: mark.knocker)
        let message = app.houseVoice(for: state).line(.liveKnock, ["knocker": name], gameID: state.gameID, round: mark.roundNumber)
        let eyebrow = TableText.text("label.liveKnock")
        heavyHaptics += 1
        if isDisplayMode {
            banner = TableBanner(id: mark.opId, kind: .liveKnock, seat: state.seat(mark.knocker), eyebrow: eyebrow, message: message)
            return
        }
        let seat = state.seat(mark.knocker)
        let session = session
        let toasts = app.toasts
        app.toasts.show(Toast(
            kind: .liveKnock,
            avatar: seat?.avatar,
            avatarName: name,
            avatarIsGuest: seat?.isGuest ?? false,
            eyebrow: eyebrow,
            message: message,
            action: mine ? Toast.Action(title: Literal.text("button.undo")) {
                Task {
                    guard session.state.liveKnock?.opId == mark.opId else { return }
                    do { try await session.markKnock(nil) } catch { toasts.show(error.localizedDescription) }
                }
            } : nil,
            duration: .seconds(5)
        ))
    }

    // MARK: Taunts

    private func taunt(_ taunt: TauntRecord) {
        let state = session.state
        if taunt.content.isCustom && !prefs.effectiveCustomTaunts { return }
        guard let text = tauntRendering.text(taunt.content, prefs.effectiveLanguageLevel) else { return }
        let to: String = switch taunt.target {
        case .table: TableText.text("label.theTable")
        case .seat(let seat): state.name(of: seat)
        }
        let eyebrow = TableText.text(taunt.content.isCustom ? "label.tauntEyebrowCustom" : "label.tauntEyebrow", ["from": taunt.fromName, "to": to])
        let sender = taunt.from.flatMap(state.seat)
        if isDisplayMode {
            banner = TableBanner(id: taunt.id, kind: .taunt, seat: sender, eyebrow: eyebrow, message: text)
            return
        }
        app.toasts.show(Toast(
            kind: .taunt,
            avatar: sender?.avatar,
            avatarName: taunt.fromName,
            avatarIsGuest: sender?.isGuest ?? false,
            eyebrow: eyebrow,
            message: text,
            onTap: { openHistory(.feed) },
            duration: .seconds(4),
            announcement: TableText.text("label.tauntAnnouncement", ["from": taunt.fromName, "to": to, "message": text])
        ))
    }

    // MARK: On the record

    private func record(_ audit: AuditEntry) {
        let state = session.state
        let voice = app.houseVoice(for: state)
        let message: String
        var tab = HistoryTab.record
        switch audit.change {
        case .roundEdited(let round, _, _, _):
            message = voice.line("H-02", ["name": audit.actor.name, "r": round])
        case .plannedRoundsChanged(let change) where change.after > change.before:
            message = voice.line("G-05", ["name": audit.actor.name, "n": change.after - change.before, "total": change.after])
        case .duplicateRound(let round):
            message = voice.line("H-06", ["r": round])
            tab = .scores
        case .lateOperation(_, let reason) where reason == .afterFinish:
            message = voice.line("H-05", ["name": audit.actor.name])
        default:
            return
        }
        guard !isDisplayMode else { return }
        app.toasts.show(Toast(message: message, onTap: { openHistory(tab) }, duration: .seconds(5)))
    }
}
