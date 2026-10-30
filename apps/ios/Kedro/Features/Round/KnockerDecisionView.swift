import SwiftUI

/// "Who knocked?" when a self-reported round has nobody or several claiming the knock (design
/// §7.4). The first tap is a proposal shown on every phone with a 5-second ring; a different tap
/// inside the ring is a contest (K-17). VoiceOver and Switch Control users get an untimed Confirm.
struct KnockerDecisionView: View {
    let session: GameSession

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @State private var isChanging = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let state = session.state
        let resolution = KnockerResolution.evaluate(state.selfReport, seats: state.seats.map(\.id), now: now)
        let voice = app.houseVoice(for: state)
        VStack(alignment: .leading, spacing: 10) {
            Text(TableText.text("label.whoKnocked"))
                .kedroFont(.label)
                .foregroundStyle(.silver)
            switch resolution {
            case .undecided:
                if let id = resolution.promptID {
                    Text(voice.line(id)).font(.callout).foregroundStyle(.cream)
                }
                picker(selected: nil, ring: nil)
            case let .proposed(proposal, deadline):
                proposalLine(proposal, state: state)
                if isChanging || untimed {
                    picker(selected: proposal.knocker, ring: nil)
                }
                let fraction = 1 - max(0, deadline.timeIntervalSince(now)) / KnockerResolution.ringDuration
                if !isChanging && !untimed {
                    picker(selected: proposal.knocker, ring: (proposal.knocker, fraction))
                }
                if untimed {
                    Button(TableText.text("button.confirm")) {
                        resolve(proposal.knocker)
                    }
                    .buttonStyle(.kedroPrimary)
                } else {
                    Text(TableText.text("label.confirmHint")).font(.caption).foregroundStyle(.silverDim)
                }
            case let .contested(earlier, later):
                Text(voice.line("K-17", [
                    "a": earlier.proposerName, "x": state.name(of: earlier.knocker),
                    "b": later.proposerName, "y": state.name(of: later.knocker),
                ]))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.cream)
                picker(selected: nil, ring: nil)
            case .ready(let knocker):
                Text(TableText.text("label.says", ["a": state.selfReport?.proposals.last?.proposerName ?? "Someone", "x": state.name(of: knocker)]))
                    .font(.callout)
                    .foregroundStyle(.cream)
                picker(selected: knocker, ring: (knocker, 1))
            case .collecting, .settled:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.surfaceRaised, in: .rect(cornerRadius: 22))
    }

    private var untimed: Bool { voiceOver || switchControl }

    private func proposalLine(_ proposal: KnockerProposal, state: GameState) -> some View {
        HStack(spacing: 8) {
            Text(TableText.text("label.says", ["a": proposal.proposerName, "x": state.name(of: proposal.knocker)]))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.cream)
            Spacer(minLength: 0)
            if !untimed {
                Button(TableText.text("button.change")) { isChanging = true }
                    .font(.callout)
                    .foregroundStyle(.kedroRed)
                    .buttonStyle(.plain)
            }
        }
    }

    private func picker(selected: SeatID?, ring: (seat: SeatID, fraction: Double)?) -> some View {
        SeatPickerRow(seats: session.state.seats, selected: selected, marksKnocker: true, ring: ring) { seat in
            propose(seat)
        }
        .padding(.horizontal, -16)
    }

    private func propose(_ seat: SeatID) {
        isChanging = false
        Task {
            do { try await session.proposeKnocker(seat) } catch { app.toasts.show(error.localizedDescription) }
        }
    }

    private func resolve(_ seat: SeatID) {
        Task {
            do { try await session.resolveKnocker(seat) } catch { app.toasts.show(error.localizedDescription) }
        }
    }
}

extension View {
    /// Commits a self-report knocker proposal when its ring runs out (design §7.4). Apply once per
    /// phone, on the Table. The proposer's phone commits at the deadline; the others back-stop a
    /// little later. The ring is untimed on the proposer's phone with VoiceOver or Switch Control.
    func selfReportAutoCommit(_ session: GameSession) -> some View {
        modifier(SelfReportAutoCommit(session: session))
    }
}

private struct SelfReportAutoCommit: ViewModifier {
    let session: GameSession

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl

    func body(content: Content) -> some View {
        content.task(id: session.state.selfReport?.proposals.last?.id) {
            guard let proposal = session.state.selfReport?.proposals.last,
                  let commitAt = KnockerResolution.commitTime(for: proposal, mySeat: session.mySeatID, isUntimed: voiceOver || switchControl)
            else { return }
            let wait = commitAt.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled else { return }
            let state = session.state
            guard case .ready(let knocker) = KnockerResolution.evaluate(state.selfReport, seats: state.seats.map(\.id), now: .now),
                  knocker == proposal.knocker, state.status.isLive
            else { return }
            try? await session.resolveKnocker(knocker)
        }
    }
}

#Preview("Nobody claimed") {
    KnockerDecisionView(session: TablePreviews.selfReportSession(reported: 5, claims: []))
        .padding()
        .background(.night)
        .previewEnvironment()
}

#Preview("Two claimed") {
    KnockerDecisionView(session: TablePreviews.selfReportSession(reported: 5, claims: [0, 2]))
        .padding()
        .background(.night)
        .previewEnvironment()
}
