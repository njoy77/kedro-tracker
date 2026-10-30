import SwiftUI

/// Settings → Sounds plays a preview of each moment. This is Settings' side of the sound pack
/// player contract (`SoundPlaying.preview(_:)` in Core/Sound, owned by talk): Settings only needs
/// the preview call, so it takes it from the environment instead of depending on the player type.
///
/// Wiring (shared need): install the real player once at the app root, e.g.
/// `.environment(\.soundPreview, SoundPreviewAction { TalkServices.shared.sound.preview($0) })`.
/// Without it, the preview buttons are hidden rather than silently doing nothing.
nonisolated struct SoundPreviewAction: Sendable {
    private let perform: @MainActor @Sendable (SoundMoment) -> Void

    init(_ perform: @escaping @MainActor @Sendable (SoundMoment) -> Void) {
        self.perform = perform
    }

    @MainActor func callAsFunction(_ moment: SoundMoment) { perform(moment) }
}

extension EnvironmentValues {
    /// Plays a sound pack moment regardless of the switches (Settings previews). nil when no
    /// player is installed.
    @Entry var soundPreview: SoundPreviewAction?
}

/// The level an outbound image renders in for this phone (receipts, share cards, Wrapped). Reads
/// `AppPreferences.outboundImagesClean`; kept as a helper for code that has only a level.
nonisolated enum OutboundImageVoice {
    static func level(preferences level: LanguageLevel, defaults: UserDefaults = .standard) -> LanguageLevel {
        let clean = defaults.object(forKey: AppPreferences.Key.outboundImagesClean) as? Bool ?? true
        return clean ? .clean : level
    }
}
