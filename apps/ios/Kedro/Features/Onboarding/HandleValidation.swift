import Foundation

/// What's wrong with a typed @handle. Messages are literal (identical in every level).
nonisolated enum HandleProblem: Error, Hashable, Sendable {
    case empty
    case tooShort
    case tooLong
    /// Something outside `[a-z0-9._]` (spaces, dashes, emoji…).
    case invalidCharacters
    /// Someone else already has it.
    case taken

    var message: String {
        switch self {
        case .empty: "Pick a handle so people can find you."
        case .tooShort: "At least \(Handle.lengthRange.lowerBound) characters."
        case .tooLong: "\(Handle.lengthRange.upperBound) characters max."
        case .invalidCharacters: "Letters, numbers, dots and underscores only."
        case .taken: "Someone already has that one."
        }
    }
}

/// Checks a typed @handle against the API's rules (lowercase, 3–20 characters, `[a-z0-9._]`).
/// Input is normalized the same way `Handle(_:)` does: trimmed, a leading "@" dropped, lowercased.
nonisolated enum HandleValidation {
    static func validate(_ input: String) -> Result<Handle, HandleProblem> {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("@") { value.removeFirst() }
        if value.isEmpty { return .failure(.empty) }
        if !value.allSatisfy(Handle.allowedCharacters.contains) { return .failure(.invalidCharacters) }
        if value.count < Handle.lengthRange.lowerBound { return .failure(.tooShort) }
        if value.count > Handle.lengthRange.upperBound { return .failure(.tooLong) }
        guard let handle = Handle(value) else { return .failure(.invalidCharacters) }
        return .success(handle)
    }

    /// Validates and checks availability against handles known to be taken.
    static func validate(_ input: String, taken: Set<String>) -> Result<Handle, HandleProblem> {
        switch validate(input) {
        case .success(let handle) where taken.contains(handle.rawValue): .failure(.taken)
        case let result: result
        }
    }

    /// Handle suggestions from a first name that aren't taken (design §5.1: "@noah, @noah.k"),
    /// best first. Falls back to numbered variants ("noah2", "noah3"…) when the usual ones are gone.
    static func uniqueSuggestions(
        firstName: String,
        lastInitial: Character? = nil,
        taken: Set<String>,
        count: Int = 3
    ) -> [Handle] {
        let base = Handle.suggestions(firstName: firstName, lastInitial: lastInitial, count: 8)
        var results = base.filter { !taken.contains($0.rawValue) }
        if results.count < count, let stem = base.first?.rawValue {
            var number = 2
            while results.count < count, number < 1000 {
                let candidate = String(stem.prefix(Handle.lengthRange.upperBound - String(number).count)) + String(number)
                if let handle = Handle(candidate), !taken.contains(candidate), !results.contains(handle) {
                    results.append(handle)
                }
                number += 1
            }
        }
        return Array(results.prefix(count))
    }
}

/// Answers "is this @handle free?". The API enforces uniqueness on `PUT /v1/players/me`; the
/// networking agent can provide a server-backed check. `DirectoryHandleAvailability` asks the
/// `PlayerDirectory` for an exact match in the meantime.
protocol HandleAvailabilityChecking: AnyObject, Sendable {
    func isAvailable(_ handle: Handle, for me: PlayerRef?) async throws -> Bool
}

/// Checks availability with `PlayerDirectory.search` (exact handle match, excluding you).
final class DirectoryHandleAvailability: HandleAvailabilityChecking {
    private let directory: any PlayerDirectory

    init(directory: any PlayerDirectory) {
        self.directory = directory
    }

    func isAvailable(_ handle: Handle, for me: PlayerRef?) async throws -> Bool {
        let matches = try await directory.search(handle.rawValue)
        return !matches.contains { $0.handle == handle && $0.ref != me }
    }
}
