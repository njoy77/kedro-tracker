import CryptoKit
import Foundation
import OSLog

/// The word lists behind the on-device taunt filter, loaded from `TauntBlocklist.json` (bundled).
///
/// Blocked terms are stored as SHA-256 hashes of their normalized form (`TauntFilter.normalizedToken`)
/// so the app never ships slurs in plain text. Profanity is plain text: it is allowed in custom
/// taunts and only used to mask them for Clean viewers (design §8.1).
nonisolated struct TauntBlocklist: Hashable, Sendable, Codable {
    var version: Int
    /// Hex SHA-256 of each blocked normalized term (single words, or up to three words joined).
    var blockedSHA256: Set<String>
    /// Words that are profane wherever they appear inside a word ("fuck" in "motherfucker").
    var profanityStems: [String]
    /// Words that are profane only as a whole word ("ass", not "assume").
    var profanityWords: Set<String>

    static let empty = TauntBlocklist(version: 0, blockedSHA256: [], profanityStems: [], profanityWords: [])

    /// The bundled list. Falls back to an empty list (logged) so the app still runs; the server
    /// check still applies.
    static func bundled(_ bundle: Bundle = .main) -> TauntBlocklist {
        guard let url = bundle.url(forResource: "TauntBlocklist", withExtension: "json") else {
            Logger(subsystem: "com.njoy77.kedro", category: "Moderation").fault("TauntBlocklist.json is missing")
            return .empty
        }
        do {
            return try JSONDecoder().decode(TauntBlocklist.self, from: Data(contentsOf: url))
        } catch {
            Logger(subsystem: "com.njoy77.kedro", category: "Moderation")
                .fault("TauntBlocklist.json is unreadable: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    /// The hash format used in `blockedSHA256`, for building lists and tests.
    static func hash(_ term: String) -> String {
        SHA256.hash(data: Data(TauntFilter.normalizedToken(term).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// The on-device half of the custom taunt filter (design §8.3): slurs and identity-based abuse
/// are blocked; profanity is allowed. The server (`POST /v1/taunts/check`) runs the second check.
///
/// Matching normalizes the text first (case, accents, common character swaps like `0`→`o` and
/// `$`→`s`, repeated letters), then checks every word, every run of up to three adjacent words
/// joined together ("s l u r", "two word" phrases), and the words with common suffixes removed.
nonisolated struct TauntFilter: Sendable {
    enum Verdict: Hashable, Sendable {
        case allowed
        case blocked
    }

    let blocklist: TauntBlocklist

    init(blocklist: TauntBlocklist) {
        self.blocklist = blocklist
    }

    /// The filter built from the bundled list.
    static let standard = TauntFilter(blocklist: .bundled())

    // MARK: Blocking

    func check(_ text: String) -> Verdict {
        guard !blocklist.blockedSHA256.isEmpty else { return .allowed }
        let tokens = Self.tokens(in: text).map(\.normalized).filter { !$0.isEmpty }
        for candidate in Self.candidates(from: tokens) where blocklist.blockedSHA256.contains(Self.sha256(candidate)) {
            return .blocked
        }
        return .allowed
    }

    func isBlocked(_ text: String) -> Bool { check(text) == .blocked }

    // MARK: Masking

    /// Masks profanity for Clean viewers: every profane word keeps its first letter
    /// ("shit" → "s***"). Everything else is shown exactly as written.
    func maskingProfanity(in text: String) -> String {
        var result = text
        // Replace from the end so earlier ranges stay valid.
        for token in Self.tokens(in: text).reversed() where isProfane(token.normalized) {
            let original = text[token.range]
            guard let first = original.first else { continue }
            result.replaceSubrange(token.range, with: String(first) + String(repeating: "*", count: max(original.count - 1, 1)))
        }
        return result
    }

    func containsProfanity(_ text: String) -> Bool {
        Self.tokens(in: text).contains { isProfane($0.normalized) }
    }

    private func isProfane(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        if blocklist.profanityWords.contains(word) || blocklist.profanityWords.contains(Self.collapsingRepeats(word)) {
            return true
        }
        return blocklist.profanityStems.contains { word.contains($0) || Self.collapsingRepeats(word).contains($0) }
    }

    // MARK: Normalization

    struct Token {
        /// Where the word is in the original text.
        var range: Range<String.Index>
        var normalized: String
    }

    /// Words in the original text with their normalized forms. A word is a run of letters, digits
    /// and the look-alike symbols `@ $ !` (so "sh!t" stays one word).
    static func tokens(in text: String) -> [Token] {
        var tokens: [Token] = []
        var start: String.Index?
        var index = text.startIndex
        func close(at end: String.Index) {
            defer { start = nil }
            guard let begin = start else { return }
            // A trailing "!" is punctuation, not a letter ("Nice!" is "nice").
            var end = end
            while end > begin, text[text.index(before: end)] == "!" { end = text.index(before: end) }
            guard end > begin else { return }
            tokens.append(Token(range: begin..<end, normalized: normalizedToken(String(text[begin..<end]))))
        }
        while index < text.endIndex {
            let character = text[index]
            if character.isLetter || character.isNumber || lookAlikes[character] != nil {
                if start == nil { start = index }
            } else if character != "'" && character != "\u{2019}" {
                close(at: index)
            }
            index = text.index(after: index)
        }
        close(at: text.endIndex)
        return tokens
    }

    /// Lowercased, accents removed, look-alike characters swapped for letters, letters only.
    static func normalizedToken(_ word: String) -> String {
        let folded = word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
        var result = ""
        for character in folded.lowercased() {
            if let swap = lookAlikes[character] {
                result.append(swap)
            } else if character.isLetter {
                result.append(character)
            }
        }
        return result
    }

    private static let lookAlikes: [Character: Character] = [
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", "$": "s", "!": "i",
    ]

    private static let suffixes = ["ing", "ers", "ed", "er", "es", "s", "y"]

    /// Every string a blocked term could hash to: single words, runs of up to three words (and
    /// any run of single letters, "s p a c e d" out), each with repeats collapsed and suffixes off.
    static func candidates(from words: [String]) -> Set<String> {
        var raw: Set<String> = []
        for start in words.indices {
            var joined = ""
            for end in start..<min(words.count, start + 3) {
                joined += words[end]
                raw.insert(joined)
            }
        }
        // Spaced-out letters: "r e t a r d".
        var run = ""
        for word in words + [""] {
            if word.count == 1 {
                run += word
            } else {
                if run.count > 2 { raw.insert(run) }
                run = ""
            }
        }
        var result: Set<String> = []
        for candidate in raw {
            for form in [candidate, collapsingRepeats(candidate)] {
                result.insert(form)
                for suffix in suffixes where form.count > suffix.count + 2 && form.hasSuffix(suffix) {
                    result.insert(String(form.dropLast(suffix.count)))
                }
            }
        }
        return result
    }

    /// "fuuuuck" → "fuck". Runs of three or more of the same letter become one; a double letter
    /// stays (so "assholes" and "hell" keep their spelling).
    static func collapsingRepeats(_ word: String) -> String {
        var result = ""
        var characters = word[...]
        while let first = characters.first {
            let run = characters.prefix { $0 == first }
            result += run.count >= 3 ? String(first) : String(run)
            characters = characters.dropFirst(run.count)
        }
        return result
    }

    private static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
