import Foundation
import OSLog

/// Runs a custom taunt through both checks before it goes out (design §8.3): the on-device
/// filter first, then the server (`POST /v1/taunts/check`).
///
/// Offline policy: tables work without internet (design §11), so when the server can't be reached
/// the on-device verdict stands. The server still filters what it stores and relays, and
/// reported taunts are retracted everywhere with `TauntRetracted`.
nonisolated struct TauntModerator: Sendable {
    enum Verdict: Hashable, Sendable {
        /// Good to send. `serverChecked` is false when only the on-device filter ran.
        case allowed(text: String, serverChecked: Bool)
        /// Blocked: show T-12 ("That one's not going out. Kedro doesn't do slurs.").
        case blocked(reason: String?)
        /// Nothing to send.
        case empty
        /// Over 80 characters.
        case tooLong
    }

    let filter: TauntFilter
    let api: any TrashTalkAPI

    func review(_ text: String) async -> Verdict {
        let trimmed = Self.prepare(text)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.count <= TauntContent.customMaxLength else { return .tooLong }
        guard filter.check(trimmed) == .allowed else { return .blocked(reason: "filter") }
        do {
            let response = try await api.checkTaunt(trimmed)
            return response.allowed ? .allowed(text: trimmed, serverChecked: true) : .blocked(reason: response.reason)
        } catch {
            Logger(subsystem: "com.njoy77.kedro", category: "Moderation")
                .info("Taunt check unavailable, using the on-device filter: \(String(describing: error), privacy: .public)")
            return .allowed(text: trimmed, serverChecked: false)
        }
    }

    /// Trims the ends and collapses runs of whitespace and newlines to one space.
    static func prepare(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
