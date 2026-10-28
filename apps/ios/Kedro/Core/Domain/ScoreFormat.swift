import Foundation

/// Formats scores with a true minus sign (U+2212), as the design requires everywhere (§3.4).
nonisolated enum ScoreFormat {
    static let minus = "\u{2212}"

    /// `-10` → "−10", `26` → "26".
    static func string(_ value: Int) -> String {
        value < 0 ? minus + String(value.magnitude) : String(value)
    }

    /// Always signed: `9` → "+9", `-10` → "−10", `0` → "0". For round deltas.
    static func signed(_ value: Int) -> String {
        value > 0 ? "+" + String(value) : string(value)
    }

    /// Spoken form for VoiceOver: "minus 10".
    static func spoken(_ value: Int) -> String {
        value < 0 ? "minus \(value.magnitude)" : String(value)
    }
}
