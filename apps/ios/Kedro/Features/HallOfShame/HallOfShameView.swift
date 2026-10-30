import SwiftUI

/// The Hall of Shame (design §12.8): the worst single moments among your people, top 3 per
/// category. There is no global Hall of Shame.
struct HallOfShameView: View {
    @Environment(AppModel.self) private var app
    @State private var scope: ShameScope = .yourPeople

    private var stats: StatsModel { .shared(for: app.store) }
    private var voice: Voice { app.voice }
    private var viewer: PlayerRef? { app.profile?.identity }

    var body: some View {
        let boards = stats.snapshot.hallOfShame(scope: scope, viewer: viewer).filter { !$0.entries.isEmpty }
        ScrollView {
            VStack(spacing: 14) {
                Text(voice.line("HS-01"))
                    .font(.subheadline)
                    .foregroundStyle(.silver)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                if viewer != nil {
                    Picker("Whose", selection: $scope) {
                        ForEach(ShameScope.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 40)
                }
                if boards.isEmpty {
                    ContentUnavailableView(
                        "Hall of Shame",
                        systemImage: "flame",
                        description: Text(voice.line(scope == .yours ? "HS-11" : "HS-10"))
                    )
                } else {
                    ForEach(boards) { board in
                        ShameBoardCard(board: board, voice: voice)
                    }
                }
            }
            .padding(16)
        }
        .background(.night)
        .navigationTitle("Hall of Shame")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.smooth, value: scope)
        .task { await stats.follow(app.store, viewer: viewer) }
    }
}

/// One category: the #1 moment in full, then #2 and #3 on a line.
struct ShameBoardCard: View {
    let board: ShameBoard
    let voice: Voice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let top = board.entries.first {
                HStack {
                    Text(board.category.name).kedroFont(.label).foregroundStyle(.kedroRed)
                    Spacer()
                    Text("\(top.tableWord) · \(top.date.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption)
                        .foregroundStyle(.silverDim)
                }
                ShameEntryRow(entry: top, voice: voice, isTop: true)
                let rest = board.entries.dropFirst()
                if !rest.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(rest.enumerated()), id: \.element.id) { offset, entry in
                            Text("\(offset + 2). \(entry.identity.name) · \(entry.shortDetail)")
                                .font(.caption)
                                .foregroundStyle(.silver)
                        }
                    }
                }
                NavigationLink(value: AppRoute.gameHistory(top.gameID)) {
                    Text(top.roundNumber.map { "View Round \($0)" } ?? "View the Game")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.kedroRed)
                        .frame(minHeight: 32)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.surface, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

/// An entry: avatar, name, the numbers, and the roast (HS-xx in the viewer's level).
struct ShameEntryRow: View {
    let entry: ShameEntry
    let voice: Voice
    var isTop = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatsAvatar(identity: entry.identity, size: .compact)
                .overlay(alignment: .topTrailing) {
                    if isTop { CrackedKMark().offset(x: 6, y: -6) }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Text(entry.identity.name).font(.kedro(.headline)).foregroundStyle(.cream)) \(Text(entry.detail).foregroundStyle(.silver))")
                    .font(.subheadline)
                Text(roast)
                    .kedroFont(.roast)
                    .foregroundStyle(.cream)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.category.name)\(isTop ? ", number one" : ""): \(entry.identity.name), \(entry.detail). \(roast)")
    }

    private var roast: String { voice.line(entry.category.copyID, entry.roastArgs) }
}

/// The #1 holder's mark: the small K with a crack through it.
struct CrackedKMark: View {
    var height: CGFloat = 16

    var body: some View {
        KMark(height: height, style: .tinted(.silver))
            .overlay {
                Canvas { context, size in
                    var crack = Path()
                    crack.move(to: CGPoint(x: size.width * 0.75, y: 0))
                    crack.addLine(to: CGPoint(x: size.width * 0.45, y: size.height * 0.4))
                    crack.addLine(to: CGPoint(x: size.width * 0.6, y: size.height * 0.55))
                    crack.addLine(to: CGPoint(x: size.width * 0.3, y: size.height))
                    context.stroke(crack, with: .color(.night), lineWidth: 1.5)
                }
            }
            .padding(2)
            .background(Circle().fill(.surfaceRaised))
            .accessibilityHidden(true)
    }
}

extension ShameEntry {
    /// The numbers without the verb, for #2 and #3: "9 into a 1", "47", "4 failed knocks".
    var shortDetail: String {
        switch category {
        case .worstHand: ScoreFormat.string(value)
        case .worstKnock: "\(ScoreFormat.string(hand ?? 0)) into a \(ScoreFormat.string(low ?? 0))"
        default: detail
        }
    }
}

#Preview {
    NavigationStack { HallOfShameView().appRouteDestinations() }
        .previewEnvironment()
}
