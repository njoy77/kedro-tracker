import Foundation

/// How a taunt reads on this phone (design §8.1).
///
/// - Canned taunts render in the **viewer's** level: every phone shows the same joke, each at its
///   own level (the recipient sees theirs).
/// - Custom taunts show exactly as written, except Clean viewers see profanity masked (the one
///   place masking is allowed, because it's someone else's words).
nonisolated enum TauntRendering {
    /// The taunt's text at a level, or nil for a canned ID this phone doesn't know.
    static func text(_ content: TauntContent, level: LanguageLevel, filter: TauntFilter = .standard) -> String? {
        switch content {
        case .canned(let id):
            guard let entry = TauntLibrary.entry(id) else { return nil }
            return Voice(level: level).line(entry)
        case .custom(let text):
            return level == .clean ? filter.maskingProfanity(in: text) : text
        }
    }

    /// The target's name: a seat's name, or "the table".
    static func targetName(_ target: TauntTarget, in state: GameState) -> String {
        switch target {
        case .table: "the table"
        case .seat(let seat): state.name(of: seat)
        }
    }

    /// The literal line above the taunt: "Ana → Noah", "Noah → the table · custom".
    static func eyebrow(for taunt: TauntRecord, in state: GameState) -> String {
        let line = "\(taunt.fromName) → \(targetName(taunt.target, in: state))"
        return taunt.content.isCustom ? "\(line) · custom" : line
    }

    /// VoiceOver: "Ana to Noah: Knocking on that? Brave."
    static func announcement(for taunt: TauntRecord, text: String, in state: GameState) -> String {
        "\(taunt.fromName) to \(targetName(taunt.target, in: state)): \(text)"
    }
}
