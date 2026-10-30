import Charts
import SwiftUI

/// The 12 Wrapped cards (design §12.9). Pure views of a `WrappedSummary` in one voice, so the
/// same card renders on screen (your level) and into a share image (Clean by default).
enum WrappedCard: Int, CaseIterable, Identifiable, Hashable {
    case cover, volume, record, rating, knock, rivals, cardLuck, mouth, trophies, shame, persona, share

    var id: Int { rawValue }

    /// Literal label for the card (accessibility, share file name).
    var label: String {
        switch self {
        case .cover: "Cover"
        case .volume: "The volume"
        case .record: "The record"
        case .rating: "The rating journey"
        case .knock: "The knock"
        case .rivals: "The nemesis and the victim"
        case .cardLuck: "Card luck"
        case .mouth: "The mouth"
        case .trophies: "Titles and badges"
        case .shame: "Your Hall of Shame year"
        case .persona: "Your Kedro persona"
        case .share: "Your year"
        }
    }

    /// The cards for a summary: Hall of Shame is skipped when there's nothing in it.
    static func cards(for summary: WrappedSummary) -> [WrappedCard] {
        allCases.filter { $0 != .shame || !summary.shame.isEmpty }
    }
}

/// One card, full-bleed on the Wrapped background.
struct WrappedCardView: View {
    let card: WrappedCard
    let summary: WrappedSummary
    let voice: Voice

    var body: some View {
        VStack(spacing: 18) {
            if card != .cover && card != .share && card != .persona {
                Text("Your \(String(summary.year)) · \(card.label)")
                    .kedroFont(.label)
                    .foregroundStyle(Color(white: 0.75))
            }
            content
        }
        .foregroundStyle(WrappedStyle.cream)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WrappedBackground() }
    }

    @ViewBuilder
    private var content: some View {
        switch card {
        case .cover: cover
        case .volume: volume
        case .record: record
        case .rating: rating
        case .knock: knock
        case .rivals: rivals
        case .cardLuck: cardLuck
        case .mouth: mouth
        case .trophies: trophies
        case .shame: shame
        case .persona: persona
        case .share: shareCard
        }
    }

    // MARK: Cards

    private var cover: some View {
        VStack(spacing: 18) {
            LogoView(width: 200)
            Text(voice.line("WR-01", ["year": String(summary.year)]))
                .kedroFont(.label)
                .textCase(.uppercase)
            StatsAvatar(identity: summary.identity, ref: summary.player, size: .profile, ring: .focus)
            Text(summary.identity.name).kedroFont(.display)
            Text(voice.line("WR-02")).kedroFont(.roast)
        }
    }

    private var volume: some View {
        VStack(spacing: 20) {
            WrappedBigNumber(value: "\(summary.games)", caption: "games")
            HStack(spacing: 10) {
                WrappedTile(value: "\(summary.rounds)", caption: "rounds")
                WrappedTile(value: hoursText, caption: "hours")
                WrappedTile(value: "\(summary.people)", caption: "people")
            }
            Text(voice.line("WR-03", ["games": summary.games, "hours": hoursText, "people": summary.people]))
                .font(.title3)
        }
    }

    private var hoursText: String {
        summary.hours < 10 ? String(format: "%.1f", summary.hours) : "\(Int(summary.hours.rounded()))"
    }

    private var record: some View {
        VStack(spacing: 20) {
            WrappedBigNumber(value: "\(summary.wins)", caption: "wins")
            Text(voice.line("WR-04", [
                "wins": summary.wins, "rate": Int((summary.winRate * 100).rounded()),
                "verdict": voice.line(summary.isWinRateHigh ? "WR-05" : "WR-06"),
            ]))
            .font(.title3)
            Chart(summary.finishes.sorted(by: { $0.key < $1.key }), id: \.key) { finish in
                BarMark(x: .value("Finish", Rank(position: finish.key, isShared: false).ordinal), y: .value("Games", finish.value))
                    .foregroundStyle(finish.key == 1 ? WrappedStyle.gold : WrappedStyle.cream.opacity(0.7))
                    .annotation(position: .top) {
                        Text("\(finish.value)").font(.caption.weight(.semibold)).foregroundStyle(WrappedStyle.cream)
                    }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(WrappedStyle.cream) }
            }
            .frame(height: 160)
            .accessibilityLabel("Finishes: " + summary.finishes.sorted(by: { $0.key < $1.key }).map { "\(Rank(position: $0.key, isShared: false).ordinal) \($0.value) times" }.joined(separator: ", "))
        }
    }

    private var rating: some View {
        VStack(spacing: 18) {
            WrappedBigNumber(value: summary.ratingNow.formatted(), caption: summary.currentRank.map { "#\($0.label) global" } ?? "rating")
            Chart(summary.ratingLine) { point in
                LineMark(x: .value("Date", point.date), y: .value("Rating", point.rating))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(WrappedStyle.red)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                AreaMark(x: .value("Date", point.date), yStart: .value("Floor", ratingFloor), yEnd: .value("Rating", point.rating))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [WrappedStyle.red.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
            }
            .chartYScale(domain: ratingFloor...ratingCeiling)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(WrappedStyle.cream)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(WrappedStyle.cream.opacity(0.15))
                    AxisValueLabel().foregroundStyle(WrappedStyle.cream)
                }
            }
            .frame(height: 220)
            .accessibilityLabel("Rating from \(summary.ratingStart) to \(summary.ratingNow), peak \(summary.ratingPeak)")
            Text(voice.line("WR-07", ["start": summary.ratingStart.formatted(), "peak": summary.ratingPeak.formatted(), "now": summary.ratingNow.formatted()]))
                .font(.title3)
        }
    }

    private var ratingFloor: Double { (summary.ratingLine.map(\.rating).min() ?? 1000) - 15 }
    private var ratingCeiling: Double { (summary.ratingLine.map(\.rating).max() ?? 1000) + 15 }

    private var knock: some View {
        VStack(spacing: 18) {
            WrappedBigNumber(value: "\(summary.knocks)", caption: "knocks")
            Text(voice.line("WR-08", [
                "knocks": summary.knocks, "success": Int((summary.knockSuccess * 100).rounded()),
                "value": summary.favoriteKnockValue.map(ScoreFormat.string) ?? "none",
            ]))
            .font(.title3)
            if let best = summary.bestKnock {
                Text("Best: knocked on \(ScoreFormat.string(best.hand)) at \(best.tableWord) and landed it.")
                    .font(.callout)
            }
            if let worst = summary.worstKnock {
                Text(voice.line("WR-09", [
                    "hand": worst.hand, "low": worst.lowestOther ?? worst.hand,
                    "date": worst.date.formatted(.dateTime.month(.wide).day()),
                ]))
                .kedroFont(.roast)
            }
        }
    }

    private var rivals: some View {
        VStack(spacing: 24) {
            if let nemesis = summary.nemesis {
                VStack(spacing: 6) {
                    Text("The nemesis").kedroFont(.label)
                    Text(nemesis.name).kedroFont(.display)
                    Text(voice.line("WR-10", ["name": nemesis.name, "n": nemesis.count])).font(.title3)
                }
            }
            if let victim = summary.victim {
                VStack(spacing: 6) {
                    Text("The victim").kedroFont(.label)
                    Text(victim.name).kedroFont(.display)
                    Text(voice.line("WR-11", ["name": victim.name, "n": victim.count])).font(.title3)
                }
            }
            if summary.nemesis == nil && summary.victim == nil {
                Text("Nobody beat you and you beat nobody. Statistically wild.").font(.title3)
            }
        }
    }

    private var cardLuck: some View {
        VStack(spacing: 20) {
            HStack(spacing: 10) {
                WrappedTile(value: "\(summary.redKings)", caption: "red Kings")
                WrappedTile(value: "\(summary.ghostHands)", caption: "ghost hands")
                WrappedTile(value: ScoreFormat.string(summary.biggestHand), caption: "biggest hand")
            }
            Text(voice.line("WR-12", ["kings": summary.redKings, "ghosts": summary.ghostHands, "big": summary.biggestHand]))
                .font(.title3)
        }
    }

    private var mouth: some View {
        VStack(spacing: 20) {
            WrappedBigNumber(value: "\(summary.tauntsSent)", caption: "taunts")
            if summary.tauntsSent > 0 {
                Text(voice.line("WR-13", [
                    "taunts": summary.tauntsSent, "taunt": tauntText,
                    "name": summary.mostTaunted?.name ?? "the table",
                ]))
                .font(.title3)
            } else {
                Text("Not a single taunt all year. Who are you saving it for.").font(.title3)
            }
        }
    }

    /// The favorite taunt as the viewer reads it.
    private var tauntText: String {
        switch summary.favoriteTaunt {
        case .canned(let id):
            let line = voice.line(id)
            return line == id ? "a classic" : line
        case .custom(let text):
            return text
        case nil:
            return "none"
        }
    }

    private var trophies: some View {
        VStack(spacing: 18) {
            WrappedBigNumber(value: "\(summary.badges.count)", caption: "badges this year")
            if !summary.badges.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                    ForEach(summary.badges.prefix(12)) { award in
                        BadgeCoin(badge: award.badge, isEarned: true, size: 52, showsCategory: false)
                    }
                }
            }
            if !summary.titles.isEmpty {
                VStack(spacing: 4) {
                    Text("Titles").kedroFont(.label)
                    Text(summary.titles.map { voice.line($0.copyID) }.formatted())
                        .kedroFont(.headline)
                        .foregroundStyle(WrappedStyle.red)
                }
            }
        }
    }

    private var shame: some View {
        VStack(spacing: 16) {
            Text(voice.line("WR-14", ["n": summary.shame.count])).font(.title3)
            ForEach(summary.shame.prefix(4)) { entry in
                VStack(spacing: 4) {
                    Text(entry.category.name).kedroFont(.label).foregroundStyle(WrappedStyle.red)
                    Text(entry.detail).font(.headline)
                    Text(voice.line(entry.category.copyID, entry.roastArgs)).kedroFont(.roast)
                }
            }
        }
    }

    private var persona: some View {
        VStack(spacing: 18) {
            Text("Your \(String(summary.year)) in Kedro · Your persona").kedroFont(.label)
            StatsAvatar(identity: summary.identity, ref: summary.player, size: .profile, ring: .focus)
            Text(summary.persona.name)
                .font(.custom(KedroTextStyle.bebas, size: 76, relativeTo: .largeTitle))
                .textCase(.uppercase)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            Text(WrappedPersona.roast(voice.line(summary.persona.copyID)))
                .font(.title3)
        }
    }

    private var shareCard: some View {
        VStack(spacing: 18) {
            LogoView(width: 170)
            Text(voice.line("WR-01", ["year": String(summary.year)])).kedroFont(.label).textCase(.uppercase)
            Text(summary.persona.name)
                .font(.custom(KedroTextStyle.bebas, size: 56, relativeTo: .largeTitle))
                .textCase(.uppercase)
            Text(summary.identity.name).kedroFont(.headline)
            HStack(spacing: 10) {
                WrappedTile(value: "\(summary.wins)–\(summary.games - summary.wins)", caption: "won–lost")
                WrappedTile(value: StatsFormat.percent(summary.winRate), caption: "win rate")
                WrappedTile(value: summary.ratingNow.formatted(), caption: "rating, peak \(summary.ratingPeak.formatted())")
            }
            if let nemesis = summary.nemesis {
                Text("Nemesis: \(nemesis.name), \(nemesis.count) times.").kedroFont(.roast)
            }
        }
    }
}

// MARK: - Pieces

/// Fixed Wrapped colors: the cards are always dark (they're shared as images).
enum WrappedStyle {
    static let cream = Color(red: 0xF5 / 255, green: 0xEF / 255, blue: 0xE6 / 255)
    static let red = Color(red: 0xE6 / 255, green: 0x39 / 255, blue: 0x46 / 255)
    static let gold = Color(red: 0xF5 / 255, green: 0xC8 / 255, blue: 0x42 / 255)
    static let night = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0E / 255)
}

/// The mockup's red glow over near-black.
struct WrappedBackground: View {
    var body: some View {
        ZStack {
            WrappedStyle.night
            RadialGradient(colors: [Color(red: 0x5A / 255, green: 0x0F / 255, blue: 0x19 / 255), .clear], center: .top, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(red: 0x2A / 255, green: 0x0A / 255, blue: 0x10 / 255), .clear], center: .bottom, startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

private struct WrappedBigNumber: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.custom(KedroTextStyle.bebas, size: 120, relativeTo: .largeTitle))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(caption).kedroFont(.label)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WrappedTile: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).kedroFont(.scoreCompact).lineLimit(1).minimumScaleFactor(0.5)
            Text(caption).font(.caption2).foregroundStyle(Color(white: 0.7)).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(Color(red: 0x13 / 255, green: 0x13 / 255, blue: 0x1A / 255), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

extension WrappedPersona {
    /// The persona line without its leading "THE CLOSER." (the card sets the name big).
    static func roast(_ line: String) -> String {
        guard let range = line.range(of: ". ") else { return line }
        let head = line[..<range.lowerBound]
        guard head == head.uppercased() else { return line }
        return String(line[range.upperBound...])
    }
}

#Preview("Persona card") {
    if let summary = StatsSnapshot.preview.wrapped(for: PreviewData.noah.ref, year: 2026) {
        WrappedCardView(card: .persona, summary: summary, voice: Voice(level: .unhinged))
    } else {
        Text("Not enough games")
    }
}

#Preview("Rating card") {
    if let summary = StatsSnapshot.preview.wrapped(for: PreviewData.noah.ref, year: 2026) {
        WrappedCardView(card: .rating, summary: summary, voice: Voice(level: .clean))
    } else {
        Text("Not enough games")
    }
}
