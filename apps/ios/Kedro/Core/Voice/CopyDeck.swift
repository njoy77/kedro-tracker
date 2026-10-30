import Foundation

/// One voice string in all three language levels (`docs/kedro-ios-copy.md`).
///
/// Templates use `{variables}` (`{name}`, `{knocker}`, `{hand}`, …) that `Voice` substitutes.
nonisolated struct CopyEntry: Hashable, Sendable, Identifiable {
    /// The copy deck ID ("K-06") or a literal key ("button.recordRound").
    let id: String
    /// What the line is for (the deck's "Moment" column), for reference only.
    let moment: String
    let clean: String
    let spicy: String
    let unhinged: String

    /// A leveled line. A nil level means "=" in the deck: same as the level to its left.
    init(_ id: String, _ moment: String, clean: String, spicy: String? = nil, unhinged: String? = nil) {
        self.id = id
        self.moment = moment
        self.clean = clean
        self.spicy = spicy ?? clean
        self.unhinged = unhinged ?? spicy ?? clean
    }

    /// A literal string: identical in every level (copy deck §20).
    static func literal(_ id: String, _ moment: String, _ text: String) -> CopyEntry {
        CopyEntry(id, moment, clean: text)
    }

    func text(for level: LanguageLevel) -> String {
        switch level {
        case .clean: clean
        case .spicy: spicy
        case .unhinged: unhinged
        }
    }

    /// The same text at every level.
    var isLiteral: Bool { clean == spicy && spicy == unhinged }
}

/// Every voice string, keyed by ID. `CopyDeck.standard` is the whole deck; feature folders that
/// need extra strings (for example more canned taunts) keep their own `[CopyEntry]` and either
/// resolve them directly with `Voice.line(_ entry:)` or build `CopyDeck.standard.merging(_:)`.
nonisolated struct CopyDeck: Sendable {
    let entries: [String: CopyEntry]

    init(_ entries: [CopyEntry]) {
        self.entries = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    subscript(id: String) -> CopyEntry? { entries[id] }

    /// A deck with extra entries added (an extra entry with an existing ID replaces it).
    func merging(_ extra: [CopyEntry]) -> CopyDeck {
        CopyDeck(Array(entries.values) + extra)
    }

    /// IDs that are literal by contract (copy deck §21): identical in every level.
    static let literalPrefixes = ["button.", "rule.", "fact.", "verdict.", "delta.", "audit.", "a11y.", "error.fix.", "label."]

    static func isLiteralKey(_ id: String) -> Bool {
        literalPrefixes.contains { id.hasPrefix($0) }
    }

    /// The whole copy deck.
    static let standard = CopyDeck(
        onboarding + joining + rounds + banter + gameEnd + history + rivalry + system
            + taunts + receipts + badges + dealer + titles + hallOfShame + wrapped + sounds + literals
    )
}

/// Moments with several variants: `Voice` picks one with a stable hash so every phone shows the
/// same line (design §4.1). Each case lists its variant IDs.
nonisolated enum VoiceMoment: String, Sendable, CaseIterable {
    case knockLanded, knockLandedLow, knockTied, knockFailed, knockFailedBig, knockFailedByOne
    case beatTheKnocker, redKing, bothRedKings, hugeHand, liveKnock
    case learnerFailedKnock, learnerBigHand, learnerTiedKnock
    case dealerLine

    var variantIDs: [String] {
        switch self {
        case .knockLanded: ["K-01", "K-02"]
        case .knockLandedLow: ["K-03", "K-02"]
        case .knockTied: ["K-04", "K-05"]
        case .knockFailed: ["K-06", "K-07"]
        case .knockFailedBig: ["K-08"]
        case .knockFailedByOne: ["K-09"]
        case .beatTheKnocker: ["K-10"]
        case .redKing: ["K-12"]
        case .bothRedKings: ["K-13"]
        case .hugeHand: ["K-20"]
        case .liveKnock: ["K-21", "K-22"]
        case .learnerFailedKnock: ["K-30"]
        case .learnerBigHand: ["K-31"]
        case .learnerTiedKnock: ["K-32"]
        case .dealerLine: ["D-02", "D-03"]
        }
    }
}
