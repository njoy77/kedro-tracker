import Foundation

/// The Round sheet's state machine (design §7.1–§7.3): who knocked, each player's hand, which row
/// has focus, and what the primary button does. Pure and value-typed so it's unit-tested; the
/// view only renders it and forwards taps.
///
/// Also drives corrections (design §9.2): `RoundEntry(editing:)` starts with every value filled
/// and the first keystroke on the tapped row replaces the old value.
nonisolated struct RoundEntry: Hashable, Sendable {
    /// Where the pre-filled knocker came from.
    enum KnockerSource: Hashable, Sendable {
        /// A live knock marked by someone (design §7.5): "(marked live by Ana)".
        case liveKnock(markedBy: String)
        /// The round being corrected.
        case saved
    }

    /// What the wide button does right now.
    enum PrimaryAction: Hashable, Sendable {
        /// "Next: Ana ›": commit and move on.
        case next(SeatID)
        /// "Save Round 6" / "Save Change" (enabled only when `canSave`).
        case save
    }

    let roundNumber: Int
    /// Seats in clockwise order.
    let seatOrder: [SeatID]
    private(set) var knocker: SeatID?
    private(set) var knockerSource: KnockerSource?
    /// The knocker went out with an inherent knock (played all four cards): their hand is 0, and
    /// they take −10 if lowest alone but never the +10.
    private(set) var isInherent = false
    private(set) var entries: [SeatID: HandEntry]
    private(set) var focus: SeatID?
    /// Rows whose pre-filled value is replaced by the next digit typed (corrections, Fix {name}).
    private(set) var replacesOnType: Set<SeatID> = []
    /// The typo guard shows at most once per round (design §7.2).
    private(set) var typoGuardShown = false
    /// The round being corrected, if this is an edit.
    let original: Round?

    /// A new round. `liveKnock` pre-fills the knocker.
    init(roundNumber: Int, seats: [SeatID], liveKnock: LiveKnock? = nil) {
        self.roundNumber = roundNumber
        seatOrder = seats
        entries = Dictionary(uniqueKeysWithValues: seats.map { ($0, HandEntry.empty) })
        original = nil
        if let liveKnock, seats.contains(liveKnock.knocker) {
            knocker = liveKnock.knocker
            knockerSource = .liveKnock(markedBy: liveKnock.markedByName)
        }
        focus = rows.first
    }

    /// A correction of a saved round, focused on the tapped seat.
    init(editing round: Round, seats: [SeatID], focus: SeatID?) {
        roundNumber = round.number
        seatOrder = seats
        original = round
        knocker = round.knocker
        isInherent = round.isInherentKnock
        knockerSource = .saved
        var entries: [SeatID: HandEntry] = [:]
        for seat in seats {
            entries[seat] = round.hands[seat].map(HandEntry.init(value:)) ?? .empty
        }
        self.entries = entries
        let start = focus.flatMap { seats.contains($0) ? $0 : nil } ?? round.knocker ?? seats.first
        self.focus = start
        replacesOnType = Set([start].compactMap(\.self))
    }

    var isEditing: Bool { original != nil }

    // MARK: Rows

    /// Knocker first, then seat order (design §7.1).
    var rows: [SeatID] {
        guard let knocker else { return seatOrder }
        return [knocker] + seatOrder.filter { $0 != knocker }
    }

    func entry(_ seat: SeatID) -> HandEntry { entries[seat] ?? .empty }

    func value(_ seat: SeatID) -> Int? { entry(seat).value }

    /// Every hand, once all are in.
    var hands: [SeatID: Int]? {
        var result: [SeatID: Int] = [:]
        for seat in seatOrder {
            guard let value = value(seat) else { return nil }
            result[seat] = value
        }
        return result
    }

    var isComplete: Bool { hands != nil }

    /// Save needs a knocker and every hand (design §7.1).
    var canSave: Bool { knocker != nil && isComplete }

    /// For corrections: true once something differs from the saved round.
    var hasChanges: Bool {
        guard let original else { return true }
        return original.knocker != knocker || original.isInherentKnock != isInherent || hands != original.hands
    }

    var primaryAction: PrimaryAction {
        if isComplete { return .save }
        return nextEmptyRow(after: focus).map(PrimaryAction.next) ?? .save
    }

    /// The first empty row after `seat` in row order, wrapping, other than `seat` itself.
    func nextEmptyRow(after seat: SeatID?) -> SeatID? {
        let rows = rows
        guard !rows.isEmpty else { return nil }
        let start = seat.flatMap { rows.firstIndex(of: $0) } ?? -1
        for offset in 1...rows.count {
            let candidate = rows[(start + offset) % rows.count]
            if candidate != seat, value(candidate) == nil { return candidate }
        }
        return nil
    }

    /// Previous and next rows for the AX layout's ‹ › header.
    func neighbor(of seat: SeatID?, step: Int) -> SeatID? {
        let rows = rows
        guard let seat, let index = rows.firstIndex(of: seat) else { return rows.first }
        let target = index + step
        return rows.indices.contains(target) ? rows[target] : nil
    }

    // MARK: Knocker

    /// One tap selects the knocker (tap again to clear). If nothing's been typed yet, focus jumps
    /// to the knocker, who is now the first row.
    mutating func selectKnocker(_ seat: SeatID?) {
        guard seat.map(seatOrder.contains) ?? true else { return }
        let nothingTyped = entries.values.allSatisfy(\.isEmpty)
        knocker = seat == knocker ? nil : seat
        knockerSource = nil
        isInherent = false
        if nothingTyped, !isEditing { focus = rows.first }
    }

    /// Marks the knock as inherent (or regular again). Inherent fills the knocker's hand with 0
    /// and moves on to the next empty row.
    mutating func setInherent(_ on: Bool) {
        guard let knocker else { return }
        isInherent = on
        guard on else { return }
        entries[knocker] = HandEntry(value: 0)
        replacesOnType.remove(knocker)
        if focus == knocker || focus == nil { focus = nextEmptyRow(after: knocker) ?? focus }
    }

    /// A live knock marked while the sheet is open pre-fills the knocker, unless one is picked.
    mutating func applyLiveKnock(_ mark: LiveKnock?) {
        guard let mark, knocker == nil, !isEditing, mark.roundNumber == roundNumber, seatOrder.contains(mark.knocker) else { return }
        let nothingTyped = entries.values.allSatisfy(\.isEmpty)
        knocker = mark.knocker
        knockerSource = .liveKnock(markedBy: mark.markedByName)
        if nothingTyped { focus = rows.first }
    }

    // MARK: Typing

    mutating func setFocus(_ seat: SeatID) {
        guard seatOrder.contains(seat) else { return }
        focus = seat
    }

    /// The most negative magnitude a seat may type: the red Kings not already in other hands.
    func redKingsLeft(for seat: SeatID) -> Int {
        let used = seatOrder.filter { $0 != seat }.reduce(0) { $0 + entry($1).redKings }
        return max(0, CardFace.redKingsPerDeck - used)
    }

    /// Red Kings still available to the focused hand in Card mode (design §7.3: after two in one
    /// round, the key disables and says why).
    var redKingsLeftForFocus: Int {
        guard let focus else { return 0 }
        return redKingsLeft(for: focus) - entry(focus).redKings
    }

    /// Applies a pad key to the focused row. Returns false if the key was refused.
    @discardableResult
    mutating func press(_ key: PadKey) -> Bool {
        guard let focus else { return false }
        var entry = entry(focus)
        if replacesOnType.contains(focus) {
            // The first keystroke on a pre-filled value replaces it; ⌫ clears it.
            switch key {
            case .digit, .minus: entry = .empty
            case .delete:
                replacesOnType.remove(focus)
                entries[focus] = .empty
                return true
            }
        }
        guard entry.press(key, negativeLimit: redKingsLeft(for: focus)) else { return false }
        replacesOnType.remove(focus)
        entries[focus] = entry
        // A hand typed for an inherent knocker means it wasn't one: they'd have had nothing left.
        if focus == knocker, isInherent, entry.value != 0 { isInherent = false }
        return true
    }

    /// Card mode: adds a card to the focused hand.
    @discardableResult
    mutating func add(_ card: CardFace) -> Bool {
        guard let focus else { return false }
        var entry = replacesOnType.contains(focus) ? HandEntry.empty : entry(focus)
        if case .typed = entry { entry = .empty } // switching a typed value to cards starts over
        guard entry.add(card, redKingsLeft: redKingsLeftForCards(focus, current: entry)) else { return false }
        replacesOnType.remove(focus)
        entries[focus] = entry
        return true
    }

    /// Card mode ⌫: removes the last card picked.
    @discardableResult
    mutating func removeLastCard() -> Bool {
        press(.delete)
    }

    private func redKingsLeftForCards(_ seat: SeatID, current: HandEntry) -> Int {
        redKingsLeft(for: seat) - current.redKings
    }

    /// Next: commit the focused value and move to the next empty row.
    mutating func advance() {
        guard case .next(let target) = primaryAction else { return }
        focus = target
    }

    // MARK: Typo guard

    /// Call at Save. Returns the hand to question (K-11) the first time only; nil means save.
    mutating func typoCheck() -> TypoGuard.Flag? {
        guard !typoGuardShown, let hands else { return nil }
        guard let flag = TypoGuard.flag(hands, order: seatOrder) else { return nil }
        typoGuardShown = true
        return flag
    }

    /// "Fix {name}": focus that row; the next digit replaces the value.
    mutating func fix(_ seat: SeatID) {
        guard seatOrder.contains(seat) else { return }
        focus = seat
        replacesOnType.insert(seat)
    }

    // MARK: Verdict and previews

    /// The verdict line (design §7.1): resolves once the knocker's value and at least one other are
    /// in, and updates as values come in.
    var verdict: RoundVerdict? {
        guard let knocker, let hand = value(knocker) else { return nil }
        let others = rows.filter { $0 != knocker }.compactMap { seat in value(seat).map { (seat, $0) } }
        guard let lowest = others.min(by: { $0.1 < $1.1 }) else { return nil }
        if hand > lowest.1 {
            return isInherent
                ? .inherentBeaten(knocker: knocker, hand: hand, by: lowest.0, low: lowest.1)
                : .failed(knocker: knocker, hand: hand, by: lowest.0, low: lowest.1)
        }
        if isComplete {
            return hand < lowest.1 ? .landed(knocker: knocker, hand: hand) : .tied(knocker: knocker, hand: hand, with: lowest.0)
        }
        return hand < lowest.1 ? .leading(knocker: knocker, hand: hand) : .tiedSoFar(knocker: knocker, hand: hand, with: lowest.0)
    }

    /// The row's preview: "2 → −10". Hand value for everyone but the knocker, whose score follows
    /// the verdict so far.
    func previewScore(_ seat: SeatID) -> Int? {
        guard let hand = value(seat) else { return nil }
        guard seat == knocker, let verdict else { return hand }
        return verdict.knockerScore
    }

    /// The round to save, once complete.
    var round: Round? {
        guard let hands, let knocker else { return nil }
        return Round(number: roundNumber, hands: hands, knocker: knocker, isInherent: isInherent && hands[knocker] == 0)
    }
}

/// The verdict line under the rows.
nonisolated enum RoundVerdict: Hashable, Sendable {
    /// In progress, knocker lowest so far (K-18).
    case leading(knocker: SeatID, hand: Int)
    /// In progress, knocker tied with someone so far.
    case tiedSoFar(knocker: SeatID, hand: Int, with: SeatID)
    /// Decided as soon as anyone is lower.
    case failed(knocker: SeatID, hand: Int, by: SeatID, low: Int)
    /// All in: strictly lowest.
    case landed(knocker: SeatID, hand: Int)
    /// All in: tied for lowest.
    case tied(knocker: SeatID, hand: Int, with: SeatID)
    /// An inherent knock someone beat: no penalty (decided as soon as anyone is lower).
    case inherentBeaten(knocker: SeatID, hand: Int, by: SeatID, low: Int)

    var knocker: SeatID {
        switch self {
        case .leading(let knocker, _), .tiedSoFar(let knocker, _, _), .failed(let knocker, _, _, _),
             .landed(let knocker, _), .tied(let knocker, _, _), .inherentBeaten(let knocker, _, _, _):
            knocker
        }
    }

    var isFinal: Bool {
        switch self {
        case .failed, .landed, .tied, .inherentBeaten: true
        case .leading, .tiedSoFar: false
        }
    }

    /// The knocker's score if it ended here.
    var knockerScore: Int {
        switch self {
        case .leading, .landed: Scoring.landedScore
        case .tiedSoFar(_, let hand, _), .tied(_, let hand, _), .inherentBeaten(_, let hand, _, _): hand
        case .failed(_, let hand, _, _): hand + Scoring.failedPenalty
        }
    }

    /// The literal line, e.g. "Sam knocked on 1 · lowest at the table · landed −10".
    func text(name: (SeatID) -> String) -> String {
        switch self {
        case let .leading(knocker, hand):
            Voice(level: .clean).line("K-18", ["knocker": name(knocker), "hand": hand])
        case let .tiedSoFar(knocker, hand, _):
            TableText.text("label.verdict.tiedSoFar", ["knocker": name(knocker), "hand": hand])
        case let .failed(knocker, hand, by, low):
            TableText.text("label.verdict.failed", ["knocker": name(knocker), "hand": hand, "name": name(by), "low": low])
        case let .landed(knocker, hand):
            TableText.text("label.verdict.landed", ["knocker": name(knocker), "hand": hand])
        case let .tied(knocker, hand, _):
            TableText.text("label.verdict.tied", ["knocker": name(knocker), "hand": hand])
        case let .inherentBeaten(knocker, _, by, low):
            TableText.text("label.verdict.inherentBeaten", ["knocker": name(knocker), "name": name(by), "low": low])
        }
    }
}

/// The typo guard (design §7.2): at Save, a hand is questioned if it's ≥ 25 and at least double the
/// next-highest hand, or ≥ 45.
nonisolated enum TypoGuard {
    struct Flag: Hashable, Sendable, Identifiable {
        var seat: SeatID
        var hand: Int
        var id: SeatID { seat }
    }

    static let doubleThreshold = 25
    static let absoluteThreshold = 45

    /// The hand to question, if any: the highest suspicious one (seat order breaks ties).
    static func flag(_ hands: [SeatID: Int], order: [SeatID]) -> Flag? {
        let ordered = order.compactMap { seat in hands[seat].map { (seat, $0) } }
        let suspicious = ordered.filter { seat, hand in
            if hand >= absoluteThreshold { return true }
            guard hand >= doubleThreshold else { return false }
            let others = ordered.filter { $0.0 != seat }.map(\.1)
            guard let nextHighest = others.max() else { return false }
            return hand >= 2 * nextHighest
        }
        guard let worst = suspicious.max(by: { $0.1 < $1.1 }) else { return nil }
        // max(by:) returns the last of equal maxima; prefer the earliest seat.
        let first = suspicious.first { $0.1 == worst.1 } ?? worst
        return Flag(seat: first.0, hand: first.1)
    }
}
