import SwiftUI

/// How the Table renders a taunt in a toast or on display mode, as an adapter so this feature
/// doesn't depend on `Features/Talk` (which owns the full canned library) or `Core/Moderation`
/// (which owns masking for Clean recipients).
///
/// The default is Talk's renderer (`TauntRendering`): the full canned library in the viewer's
/// level, and custom taunts with profanity masked for Clean viewers. `standardDeck` is the
/// deck-only fallback (TT-01…TT-14, custom as written) for tests.
nonisolated struct TableTauntRendering: Sendable {
    /// The taunt's text for a recipient at `level`, or nil to not show it at all.
    var text: @Sendable (_ content: TauntContent, _ level: LanguageLevel) -> String?

    init(text: @escaping @Sendable (_ content: TauntContent, _ level: LanguageLevel) -> String?) {
        self.text = text
    }

    /// Canned taunts from `CopyDeck.standard`; custom ones as written. An unknown canned ID is
    /// not shown (rather than leaking the ID).
    static let standardDeck = TableTauntRendering { content, level in
        switch content {
        case .canned(let id):
            guard CopyDeck.standard[id] != nil else { return nil }
            return Voice(level: level).line(id)
        case .custom(let text):
            return text
        }
    }
}

extension TableTauntRendering {
    /// Talk's renderer: the full taunt library, Clean masking for custom taunts.
    static let talk = TableTauntRendering { content, level in
        TauntRendering.text(content, level: level)
    }
}

extension EnvironmentValues {
    @Entry var tauntRendering: TableTauntRendering = .talk
}
