import Foundation

/// A unique public @handle (PRD §3.1). Lowercase, 3–20 characters from `[a-z0-9._]`.
///
/// Stored and sent without the "@"; `description` adds it for display.
/// JSON: the bare string, e.g. `"noah.k"`. Uniqueness is enforced by the API (`PUT /v1/players/me`).
nonisolated struct Handle: Hashable, Sendable, Codable, CustomStringConvertible, Comparable {
    static let lengthRange = 3...20
    static let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789._")

    let rawValue: String

    /// Normalizes (trims, drops a leading "@", lowercases) and validates. Returns nil if invalid.
    init?(_ input: String) {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") { value.removeFirst() }
        guard Self.isValid(value) else { return nil }
        rawValue = value
    }

    /// For constants known to be valid (sample data, tests). Asserts in debug builds.
    init(constant: String) {
        assert(Self.isValid(constant), "Invalid handle constant \(constant)")
        rawValue = constant
    }

    /// "@noah"
    var description: String { "@" + rawValue }

    static func isValid(_ value: String) -> Bool {
        lengthRange.contains(value.count) && value.allSatisfy(allowedCharacters.contains)
    }

    static func < (lhs: Handle, rhs: Handle) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Handle suggestions from a first name (design §5.1: "@noah, @noah.k"), best first.
    /// The caller checks availability with the API; these are only well-formed candidates.
    static func suggestions(firstName: String, lastInitial: Character? = nil, count: Int = 4) -> [Handle] {
        let base = String(
            firstName
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX"))
                .lowercased()
                .filter { allowedCharacters.contains($0) && $0 != "." }
                .prefix(16)
        )
        let stem = base.count >= 3 ? base : base + String(repeating: "x", count: 3 - base.count)
        var candidates = [stem]
        if let lastInitial, let initial = lastInitial.lowercased().first, allowedCharacters.contains(initial) {
            candidates.append("\(stem).\(initial)")
        }
        candidates.append(contentsOf: ["\(stem).k", "\(stem)\(stem.count)", "the.\(stem)", "\(stem)_"])
        var seen = Set<String>()
        return candidates
            .filter { seen.insert($0).inserted }
            .compactMap(Handle.init)
            .prefix(count)
            .map { $0 }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let handle = Handle(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid handle \(raw)")
        }
        self = handle
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
