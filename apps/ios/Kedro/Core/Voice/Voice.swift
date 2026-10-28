import Foundation

/// Values substituted into `{variables}`. Integers render with a true minus ("−10").
typealias VoiceArgs = [String: any CustomStringConvertible & Sendable]

/// Picks a variant so every phone shows the same line: a stable FNV-1a hash of
/// (gameID, round, key). Never Swift's `Hasher`, which is seeded per launch (design §4.1).
nonisolated struct VoiceSeed: Hashable, Sendable {
    var gameID: GameID?
    var round: Int
    var key: String

    init(gameID: GameID?, round: Int, key: String) {
        self.gameID = gameID
        self.round = round
        self.key = key
    }

    /// The 64-bit FNV-1a hash of `"<gameID>|<round>|<key>"` (empty gameID when nil).
    var hash: UInt64 {
        FNV1a.hash("\(gameID?.uuidString ?? "")|\(round)|\(key)")
    }

    func index(count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(hash % UInt64(count))
    }
}

/// 64-bit FNV-1a over UTF-8 bytes.
nonisolated enum FNV1a {
    static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    static let prime: UInt64 = 0x0000_0100_0000_01b3

    static func hash(_ string: String) -> UInt64 {
        var hash = offsetBasis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return hash
    }
}

/// Renders copy deck lines at one language level.
///
/// ```swift
/// let voice = Voice(level: .unhinged)
/// voice.line("K-21", ["knocker": "Sam"])                    // one ID
/// voice.line(.knockLanded, ["knocker": "Noah", "hand": 2],  // a moment with variants
///            seed: VoiceSeed(gameID: id, round: 5, key: "lastRound"))
/// ```
///
/// Which level to use: personal surfaces (Play, You, notifications, Live Activity) use
/// `AppModel.voice` (the viewer's level); shared table surfaces (Table, Round sheet, History,
/// game end, display mode) use `Voice.house(for:viewer:)`.
nonisolated struct Voice: Sendable {
    var level: LanguageLevel
    var deck: CopyDeck

    init(level: LanguageLevel, deck: CopyDeck = .standard) {
        self.level = level
        self.deck = deck
    }

    /// The house voice for a game: the lowest level at the table, never above the viewer's own.
    static func house(for state: GameState, viewer: LanguageLevel) -> Voice {
        Voice(level: min(state.houseLevel, viewer))
    }

    /// One line by ID. Unknown IDs return the ID itself (and fail the catalog tests).
    func line(_ id: String, _ args: VoiceArgs = [:]) -> String {
        guard let entry = deck[id] else { return id }
        return line(entry, args)
    }

    /// One line from an entry that isn't in the deck (feature-local strings).
    func line(_ entry: CopyEntry, _ args: VoiceArgs = [:]) -> String {
        Self.substitute(entry.text(for: level), args)
    }

    /// One of several variant IDs, chosen by the seed.
    func line(oneOf ids: [String], _ args: VoiceArgs = [:], seed: VoiceSeed) -> String {
        guard !ids.isEmpty else { return "" }
        return line(ids[seed.index(count: ids.count)], args)
    }

    /// A moment's variant, chosen by the seed. The seed's key defaults to the moment's name.
    func line(_ moment: VoiceMoment, _ args: VoiceArgs = [:], seed: VoiceSeed) -> String {
        line(oneOf: moment.variantIDs, args, seed: seed)
    }

    /// A moment's variant for a round of a game.
    func line(_ moment: VoiceMoment, _ args: VoiceArgs = [:], gameID: GameID, round: Int) -> String {
        line(moment, args, seed: VoiceSeed(gameID: gameID, round: round, key: moment.rawValue))
    }

    /// Replaces `{variable}` with its argument. Unknown variables are left as written.
    static func substitute(_ template: String, _ args: VoiceArgs) -> String {
        guard template.contains("{"), !args.isEmpty else { return template }
        var result = ""
        var remainder = template[...]
        while let open = remainder.firstIndex(of: "{") {
            result += remainder[..<open]
            guard let close = remainder[open...].firstIndex(of: "}") else { break }
            let name = String(remainder[remainder.index(after: open)..<close])
            if let value = args[name] {
                result += format(value)
            } else {
                result += remainder[open...close]
            }
            remainder = remainder[remainder.index(after: close)...]
        }
        result += remainder
        return result
    }

    private static func format(_ value: any CustomStringConvertible & Sendable) -> String {
        if let number = value as? Int { return ScoreFormat.string(number) }
        return value.description
    }
}

/// Typed helpers for the literal strings (copy deck §20). Identical in every level.
nonisolated enum Literal {
    private static let voice = Voice(level: .clean)

    static func text(_ key: String, _ args: VoiceArgs = [:]) -> String { voice.line(key, args) }

    static func recordRound(_ round: Int) -> String { text("button.recordRound", ["r": round]) }
    static func saveRound(_ round: Int) -> String { text("button.saveRound", ["r": round]) }
    static func next(_ name: String) -> String { text("button.next", ["name": name]) }
    static func letIn(_ name: String) -> String { text("button.letIn", ["name": name]) }
    static func keepHand(_ hand: Int) -> String { text("button.keepHand", ["hand": hand]) }
    static func fix(_ name: String) -> String { text("button.fix", ["name": name]) }
    static func playAgain(with name: String) -> String { text("button.playAgainWith", ["name": name]) }

    /// "Round 5. Noah knocked on 2."
    static func fact(round: Int, knocker: String, hand: Int) -> String {
        text("fact.round", ["r": round, "knocker": knocker, "hand": hand])
    }

    /// "Landed: −10." / "Tied: 5." / "Failed: 2 + 10 = 12."
    static func verdict(_ outcome: KnockOutcome, hand: Int) -> String {
        switch outcome {
        case .landed: text("verdict.landed")
        case .tied: text("verdict.tied", ["hand": hand])
        case .failed: text("verdict.failed", ["hand": hand, "score": hand + Scoring.failedPenalty])
        }
    }

    /// The knocker's delta caption: "landed · −10", "tied · 5", "failed · 2 + 10".
    static func knockerDelta(_ outcome: KnockOutcome, hand: Int) -> String {
        switch outcome {
        case .landed: text("delta.landed")
        case .tied: text("delta.tied", ["hand": hand])
        case .failed: text("delta.failed", ["hand": hand])
        }
    }

    /// A standings delta: the knock math for the knocker, otherwise the signed round score.
    static func delta(_ result: SeatRoundResult) -> String {
        if let outcome = result.outcome { return knockerDelta(outcome, hand: result.hand) }
        return ScoreFormat.signed(result.score)
    }

    /// "ROUND 6 OF 8"
    static func roundOf(_ round: Int, _ total: Int) -> String { text("label.roundOf", ["r": round, "total": total]) }

    /// "COLD DECK · NOAH DEALS"
    static func deals(word: String, dealer: String) -> String {
        text("label.deals", ["word": word.uppercased(), "name": dealer.uppercased()])
    }

    /// "COLD DECK · R6/8 · You 1st · 26"
    static func miniBar(word: String, round: Int, total: Int, rank: Rank, score: Int) -> String {
        text("label.miniBar", ["word": word.uppercased(), "r": round, "total": total, "rank": rank.ordinal, "score": score])
    }
}
