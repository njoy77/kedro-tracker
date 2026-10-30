import SwiftUI

/// Head-to-head between two people (design §12.3, PRD §5.2). When you're one of them, you're on
/// the left and the lines talk to you; between two other people the lines are literal.
struct HeadToHeadView: View {
    let a: PlayerRef
    let b: PlayerRef

    @Environment(AppModel.self) private var app
    @State private var playAgainFailed = false

    private var stats: StatsModel { .shared(for: app.store) }
    private var voice: Voice { app.voice }

    /// A rivalry is "big" once one side leads by this many.
    static let bigLead = 3

    var body: some View {
        let snapshot = stats.snapshot
        let (left, right) = sides(snapshot)
        let h2h = snapshot.headToHead(left, right)
        let leftPerson = snapshot.participant(left)
        let rightPerson = snapshot.participant(right)
        ScrollView {
            VStack(spacing: 20) {
                faceOff(h2h, left: leftPerson, right: rightPerson)
                headline(h2h, left: leftPerson, right: rightPerson)
                if h2h.gamesTogether == 0 {
                    ContentUnavailableView(
                        "Never Played",
                        systemImage: "person.2",
                        description: Text("No finished games together yet.")
                    )
                } else {
                    record(h2h, left: leftPerson, right: rightPerson)
                }
                if isMe(left), app.profile != nil {
                    Button(Literal.playAgain(with: rightPerson.name)) {
                        Task {
                            do { try await app.playAgain(with: [rightPerson]) } catch { playAgainFailed = true }
                        }
                    }
                    .buttonStyle(.kedroPrimary)
                    .disabled(app.liveGame != nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(.nightGradient)
        .navigationTitle("Head to Head")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't Open a Table", isPresented: $playAgainFailed) {
            Button(Literal.text("button.done"), role: .cancel) {}
        }
        .task { await stats.follow(app.store, viewer: app.profile?.identity) }
    }

    private func isMe(_ ref: PlayerRef) -> Bool {
        guard let me = app.profile?.identity else { return false }
        return stats.snapshot.options.canonical(me) == stats.snapshot.options.canonical(ref)
    }

    /// You on the left.
    private func sides(_ snapshot: StatsSnapshot) -> (PlayerRef, PlayerRef) {
        isMe(b) && !isMe(a) ? (b, a) : (a, b)
    }

    // MARK: Sections

    private func faceOff(_ h2h: HeadToHead, left: StatsParticipant, right: StatsParticipant) -> some View {
        HStack(alignment: .center, spacing: 24) {
            person(left, leads: h2h.leader == h2h.a)
            Text("VS").kedroFont(.display).foregroundStyle(.kedroRed).accessibilityHidden(true)
            person(right, leads: h2h.leader == h2h.b)
        }
        .padding(.top, 16)
    }

    private func person(_ person: StatsParticipant, leads: Bool) -> some View {
        NavigationLink(value: AppRoute.profile(person.ref)) {
            VStack(spacing: 6) {
                StatsAvatar(identity: person, size: .profile, ring: leads ? .winner : .none)
                Text(person.name).kedroFont(.headline).foregroundStyle(.cream)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(person.name)\(leads ? ", leads" : "")")
        .accessibilityHint("Opens the profile")
    }

    @ViewBuilder
    private func headline(_ h2h: HeadToHead, left: StatsParticipant, right: StatsParticipant) -> some View {
        VStack(spacing: 10) {
            Group {
                if let leader = h2h.leader {
                    let leaderName = leader == h2h.a ? left.name : right.name
                    let high = max(h2h.aAhead, h2h.bAhead), low = min(h2h.aAhead, h2h.bAhead)
                    Text("\(leaderName) leads \(Text("\(high)–\(low)").foregroundStyle(.gold))")
                } else {
                    Text("Level \(h2h.aAhead)–\(h2h.bAhead)")
                }
            }
            .kedroFont(.display)
            .foregroundStyle(.cream)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)

            if let line = rivalryLine(h2h, right: right) {
                Text(line)
                    .kedroFont(.roast)
                    .foregroundStyle(.cream)
                    .multilineTextAlignment(.center)
            }
            if let gap = gapLine(h2h, right: right) {
                Text(gap)
                    .font(.subheadline)
                    .foregroundStyle(.silver)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 12)
    }

    /// R-01 (they lead big), R-03 (you lead big), R-04 (dead even), from your side only.
    private func rivalryLine(_ h2h: HeadToHead, right: StatsParticipant) -> String? {
        guard isMe(h2h.a), h2h.gamesTogether > 0 else { return nil }
        if h2h.aAhead == h2h.bAhead { return voice.line("R-04", ["a": h2h.aAhead]) }
        guard h2h.gap >= Self.bigLead else { return nil }
        if h2h.leader == h2h.b { return voice.line("R-01", ["name": right.name, "n": h2h.bAhead]) }
        return voice.line("R-03", ["name": right.name, "a": h2h.aAhead, "b": h2h.bAhead])
    }

    /// R-02 when you're behind.
    private func gapLine(_ h2h: HeadToHead, right: StatsParticipant) -> String? {
        guard isMe(h2h.a), h2h.leader == h2h.b else { return nil }
        return voice.line("R-02", ["gap": h2h.gap, "name": right.name])
    }

    private func record(_ h2h: HeadToHead, left: StatsParticipant, right: StatsParticipant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(left.name).kedroFont(.label).foregroundStyle(.silver)
                Spacer()
                Text(right.name).kedroFont(.label).foregroundStyle(.silver)
            }
            .padding(.horizontal, 14)
            .accessibilityHidden(true)
            VStack(spacing: 12) {
                StatRow("Games together", value: "\(h2h.gamesTogether)", info: .gamesTogether)
                Divider().overlay(Color.rule)
                pairRow("Finished ahead", h2h.aAhead, h2h.bAhead, left: left, right: right, info: .finishedAhead)
                Divider().overlay(Color.rule)
                pairRow("Wins in shared games", h2h.aWins, h2h.bWins, left: left, right: right, info: .wins)
                Divider().overlay(Color.rule)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Knocks facing each other").font(.subheadline).foregroundStyle(.cream)
                        InfoButton(definition: .knockOutcomes)
                    }
                    HStack {
                        KnockTallyView(tally: h2h.aKnocks)
                            .accessibilityLabel("\(left.name): \(h2h.aKnocks.accessibilityLabel)")
                        Spacer()
                        KnockTallyView(tally: h2h.bKnocks)
                            .accessibilityLabel("\(right.name): \(h2h.bKnocks.accessibilityLabel)")
                    }
                }
                Divider().overlay(Color.rule)
                StatRow(label: "Average final score together", info: .averageGame) {
                    Text("\(h2h.aAverageFinal.map(StatsFormat.decimal) ?? "–") · \(h2h.bAverageFinal.map(StatsFormat.decimal) ?? "–")")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Average final score together: \(left.name) \(h2h.aAverageFinal.map(StatsFormat.decimal) ?? "none"), \(right.name) \(h2h.bAverageFinal.map(StatsFormat.decimal) ?? "none")")
                if let meeting = h2h.lastMeeting {
                    Divider().overlay(Color.rule)
                    NavigationLink(value: AppRoute.gameHistory(meeting.gameID)) {
                        StatRow(label: "Last meeting · \(meeting.tableWord)") {
                            HStack(spacing: 6) {
                                Text("\(left.name) \(ScoreFormat.string(meeting.aScore)) · \(right.name) \(ScoreFormat.string(meeting.bScore))")
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.silverDim)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(.surface, in: .rect(cornerRadius: 16))
        }
    }

    private func pairRow(_ label: String, _ left: Int, _ right: Int, left leftPerson: StatsParticipant, right rightPerson: StatsParticipant, info: StatDefinition) -> some View {
        StatRow(label: label, info: info) {
            Text("\(left) · \(right)").fontWeight(.semibold)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(leftPerson.name) \(left), \(rightPerson.name) \(right)")
    }
}

#Preview("You and Ana") {
    NavigationStack { HeadToHeadView(a: PreviewData.noah.ref, b: PreviewData.ana.ref).appRouteDestinations() }
        .previewEnvironment()
}

#Preview("Two other people") {
    NavigationStack { HeadToHeadView(a: PreviewData.ana.ref, b: PreviewData.cleo.ref) }
        .previewEnvironment()
}
