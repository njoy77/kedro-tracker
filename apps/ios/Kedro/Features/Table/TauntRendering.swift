import SwiftUI

/// How the Table renders a taunt in a toast or on display mode, as an adapter so this feature
/// doesn't depend on `Features/Talk` (which owns the full canned library) or `Core/Moderation`
/// (which owns masking for Clean recipients).
///
/// The default resolves canned taunts through the standard copy deck (`TT-01…TT-14`) and shows
/// custom taunts as written. The Talk agent can install a richer one with
/// `.environment(\.tauntRendering, …)` on the Table's cover.
nonisolated struct TauntRendering: Sendable {
    /// The taunt's text for a recipient at `level`, or nil to not show it at all.
    var text: @Sendable (_ content: TauntContent, _ level: LanguageLevel) -> String?

    init(text: @escaping @Sendable (_ content: TauntContent, _ level: LanguageLevel) -> String?) {
        self.text = text
    }

    /// Canned taunts from `CopyDeck.standard`; custom ones as written. An unknown canned ID is
    /// not shown (rather than leaking the ID).
    static let standardDeck = TauntRendering { content, level in
        switch content {
        case .canned(let id):
            guard CopyDeck.standard[id] != nil else { return nil }
            return Voice(level: level).line(id)
        case .custom(let text):
            return text
        }
    }
}

extension EnvironmentValues {
    @Entry var tauntRendering: TauntRendering = .standardDeck
}
