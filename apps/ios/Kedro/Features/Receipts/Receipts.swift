import Foundation

/// One receipt a player can send a rival after a finished game (design §8.5): a canned RC line
/// and, when it's about a knock, the literal round it's roasting.
///
/// Receipts are pre-written only. The operation carries just the `receiptKey` (`RC-xx`); every
/// phone rebuilds the line's values (`{hand}`, `{gap}`, `{low}`) from the finished game with
/// `Receipts.option(_:in:from:to:)`, so the recipient reads it in their own level.
nonisolated struct ReceiptOption: Hashable, Sendable, Identifiable {
    /// The copy ID: `RC-01`…`RC-06`.
    let key: String
    /// Values for the line's variables.
    let values: [String: Int]
    /// The round being roasted, for knock receipts.
    let roundNumber: Int?

    var id: String { key }

    var entry: CopyEntry? { CopyDeck.standard[key] }

    /// The line at a level, e.g. "Knocking on 18 is a choice. A bad choice."
    func line(level: LanguageLevel) -> String {
        Voice(level: level).line(key, values.mapValues { $0 as any CustomStringConvertible & Sendable })
    }
}

/// The receipt rules: who can get one, which lines fit, and the facts behind them.
nonisolated enum Receipts {
    /// Copy IDs, most pointed first (the order the composer offers them in).
    static let keys = ["RC-06", "RC-02", "RC-05", "RC-01", "RC-04", "RC-03"]

    /// The lines that fit this pair in a finished game, most pointed first. "Rematch" (RC-03)
    /// always fits.
    static func options(in state: GameState, from sender: SeatID, to rival: SeatID) -> [ReceiptOption] {
        keys.compactMap { option($0, in: state, from: sender, to: rival) }
    }

    /// One line for this pair, or nil when it doesn't fit (or the key is unknown).
    static func option(_ key: String, in state: GameState, from sender: SeatID, to rival: SeatID) -> ReceiptOption? {
        guard sender != rival, let mine = state.standing(for: sender), let theirs = state.standing(for: rival) else { return nil }
        switch key {
        case "RC-01":
            // You won.
            return mine.rank.position == 1 ? ReceiptOption(key: key, values: [:], roundNumber: nil) : nil
        case "RC-02":
            // They failed a knock: the worst one (the biggest margin).
            guard let round = worstFailedKnock(by: rival, in: state), let hand = round.round.hands[rival] else { return nil }
            return ReceiptOption(key: key, values: ["hand": hand], roundNumber: round.number)
        case "RC-03":
            return ReceiptOption(key: key, values: [:], roundNumber: nil)
        case "RC-04":
            // Chasing them: you finished behind.
            let gap = mine.total - theirs.total
            return gap > 0 ? ReceiptOption(key: key, values: ["gap": gap], roundNumber: nil) : nil
        case "RC-05":
            // They finished last (alone or shared), and you didn't.
            guard let worst = state.standings.map(\.total).max(), let best = state.standings.map(\.total).min(), worst != best,
                  theirs.total == worst, mine.total != worst
            else { return nil }
            return ReceiptOption(key: key, values: [:], roundNumber: nil)
        case "RC-06":
            // You beat their knock: your hand was lower than theirs on their knock.
            guard let (round, low) = beatenKnock(by: rival, beatenBy: sender, in: state) else { return nil }
            return ReceiptOption(key: key, values: ["low": low], roundNumber: round.number)
        default:
            return nil
        }
    }

    /// The people this player can still send a receipt to in Kedro: everyone else from the
    /// game, minus those already sent one (one per rival per game).
    static func recipients(in state: GameState, from sender: SeatID) -> [Seat] {
        let sent = Set(state.receipts.filter { $0.from == sender }.map(\.to))
        return state.seats.filter { $0.id != sender && !sent.contains($0.id) }
    }

    /// Whether `sender` already sent `rival` one.
    static func hasSent(in state: GameState, from sender: SeatID, to rival: SeatID) -> Bool {
        state.receipts.contains { $0.from == sender && $0.to == rival }
    }

    /// The literal round behind a knock receipt, fact and verdict on two lines:
    /// "Round 3. Noah knocked on 8.\nFailed: 8 + 10 = 18."
    static func roast(for option: ReceiptOption, in state: GameState) -> String? {
        guard let number = option.roundNumber, let record = state.round(number), let outcome = record.outcome,
              let hand = record.round.hands[record.knocker]
        else { return nil }
        return Literal.fact(round: number, knocker: state.name(of: record.knocker), hand: hand) + "\n" + Literal.verdict(outcome, hand: hand)
    }

    /// Literal eyebrow for the card: "COLD DECK · FINAL · 8 ROUNDS" (uppercased by the label style).
    static func eyebrow(for state: GameState) -> String {
        let rounds = state.rounds.count
        return "\(state.config.tableWord) · Final · \(rounds) \(rounds == 1 ? "round" : "rounds")"
    }

    // MARK: Private

    private static func worstFailedKnock(by knocker: SeatID, in state: GameState) -> RoundRecord? {
        state.rounds
            .filter { $0.knocker == knocker && $0.outcome == .failed }
            .max { margin(of: $0) < margin(of: $1) }
    }

    /// How far the knocker missed by: their hand minus the lowest other hand.
    private static func margin(of record: RoundRecord) -> Int {
        let knockerHand = record.round.hands[record.knocker] ?? 0
        let lowestOther = record.round.hands.filter { $0.key != record.knocker }.map(\.value).min() ?? knockerHand
        return knockerHand - lowestOther
    }

    private static func beatenKnock(by knocker: SeatID, beatenBy sender: SeatID, in state: GameState) -> (RoundRecord, Int)? {
        state.rounds
            .compactMap { record -> (RoundRecord, Int, Int)? in
                guard record.knocker == knocker, let theirs = record.round.hands[knocker], let mine = record.round.hands[sender],
                      mine < theirs
                else { return nil }
                return (record, mine, theirs - mine)
            }
            .max { $0.2 < $1.2 }
            .map { ($0.0, $0.1) }
    }
}
