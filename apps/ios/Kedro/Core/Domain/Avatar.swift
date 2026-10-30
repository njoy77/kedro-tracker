import Foundation

/// A player's face (design §3.5). Guests have no avatar: they render as an initial with a dashed
/// ring (`AvatarView` handles that when `avatar` is nil and the person is a guest).
///
/// JSON:
/// - `{"kind":"photo","url":"https://…/avatars/<id>.jpg"}` (a reference, never image bytes; a
///   `file://` URL is allowed locally before upload)
/// - `{"kind":"emoji","emoji":"🦊","colorIndex":3}` (`colorIndex` into `AvatarPalette`, 0–11)
/// - `{"kind":"curated","id":"horse"}`
nonisolated enum Avatar: Hashable, Sendable, Codable {
    case photo(URL)
    case emoji(String, colorIndex: Int)
    case curated(CuratedAvatarID)

    /// Emoji offered as the default for new accounts (a random one on a random color).
    static let starterEmoji = ["🦊", "🦂", "🐍", "🦉", "🐺", "🦈", "🐗", "🦅", "🐙", "🦇", "🐆", "🦏"]

    /// The number of emoji background colors (`AvatarPalette.colors.count`).
    static let emojiColorCount = 12

    /// A random starter avatar for someone who skips the avatar step.
    static func randomStarter<G: RandomNumberGenerator>(using generator: inout G) -> Avatar {
        let emoji = starterEmoji.randomElement(using: &generator) ?? "🦊"
        return .emoji(emoji, colorIndex: Int.random(in: 0..<emojiColorCount, using: &generator))
    }

    static func randomStarter() -> Avatar {
        var generator = SystemRandomNumberGenerator()
        return randomStarter(using: &generator)
    }

    private enum CodingKeys: String, CodingKey { case kind, url, emoji, colorIndex, id }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "photo":
            self = .photo(try container.decode(URL.self, forKey: .url))
        case "emoji":
            let index = try container.decode(Int.self, forKey: .colorIndex)
            self = .emoji(try container.decode(String.self, forKey: .emoji), colorIndex: index)
        case "curated":
            self = .curated(try container.decode(CuratedAvatarID.self, forKey: .id))
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown avatar kind \(kind)")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .photo(let url):
            try container.encode("photo", forKey: .kind)
            try container.encode(url, forKey: .url)
        case .emoji(let emoji, let colorIndex):
            try container.encode("emoji", forKey: .kind)
            try container.encode(emoji, forKey: .emoji)
            try container.encode(colorIndex, forKey: .colorIndex)
        case .curated(let id):
            try container.encode("curated", forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }
}

/// The 24 curated launch avatars (design §3.5). Artwork: `CuratedAvatarArt` in Core/Design.
nonisolated enum CuratedAvatarID: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case horse, joker, skull, crown, dice, glass, ghost, crow
    case bull, eye, flame, spade, wolf, shark, hustler, ace
    case redKing, lastCall, ashtray, hourglass, cardsFan, horseshoe, dagger, moon

    var id: String { rawValue }

    /// Secret avatars unlock with secret badges (design §12.6).
    var isSecret: Bool { unlockingBadge != nil }

    /// The badge that unlocks a secret avatar: Exorcism → the Ghost, Nothing to See Here → the Hustler.
    var unlockingBadge: String? {
        switch self {
        case .ghost: "Exorcism"
        case .hustler: "Nothing to See Here"
        default: nil
        }
    }

    /// Literal name, used for accessibility labels.
    var displayName: String {
        switch self {
        case .horse: "The Horse"
        case .joker: "The Joker"
        case .skull: "The Skull"
        case .crown: "The Crown"
        case .dice: "The Dice"
        case .glass: "The Glass"
        case .ghost: "The Ghost"
        case .crow: "The Crow"
        case .bull: "The Bull"
        case .eye: "The Eye"
        case .flame: "The Flame"
        case .spade: "The Spade"
        case .wolf: "The Wolf"
        case .shark: "The Shark"
        case .hustler: "The Hustler"
        case .ace: "The Ace"
        case .redKing: "The Red King"
        case .lastCall: "Last Call"
        case .ashtray: "The Ashtray"
        case .hourglass: "The Hourglass"
        case .cardsFan: "The Hand"
        case .horseshoe: "The Horseshoe"
        case .dagger: "The Dagger"
        case .moon: "The Moon"
        }
    }
}
