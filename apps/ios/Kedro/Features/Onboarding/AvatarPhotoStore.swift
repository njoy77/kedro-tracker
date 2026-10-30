import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Keeps avatar photos on this phone: crops a picked or captured image to a centered square,
/// downsizes it, and writes a JPEG to Application Support. The resulting `file://` URL is a valid
/// `Avatar.photo` until the networking agent uploads it and swaps in the remote URL.
nonisolated enum AvatarPhotoStore {
    enum PhotoError: LocalizedError {
        case unreadableImage
        case couldNotSave

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "That photo couldn't be read. Try another one."
            case .couldNotSave: "That photo couldn't be saved. Try again."
            }
        }
    }

    /// Pixel size of the stored square.
    static let pixelSize = 512

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Avatars", directoryHint: .isDirectory)
    }

    /// Crops, downsizes and saves image data. Returns the file URL for `Avatar.photo`.
    static func save(_ data: Data) throws -> URL {
        guard let square = squareImage(from: data) else { throw PhotoError.unreadableImage }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString.lowercased()).jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoError.couldNotSave
        }
        CGImageDestinationAddImage(destination, square, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw PhotoError.couldNotSave }
        return url
    }

    /// A centered square crop, downsized so its short side is `pixelSize`, with EXIF orientation applied.
    static func squareImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? pixelSize
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? pixelSize
        let shortSide = max(1, min(width, height))
        let longSide = max(width, height)
        // Thumbnail by the long side so the short side lands at `pixelSize`.
        let maxPixel = max(pixelSize, Int((Double(longSide) / Double(shortSide) * Double(pixelSize)).rounded(.up)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let side = min(thumbnail.width, thumbnail.height)
        let rect = CGRect(x: (thumbnail.width - side) / 2, y: (thumbnail.height - side) / 2, width: side, height: side)
        return thumbnail.cropping(to: rect)
    }

    /// Deletes a stored local photo (when the player picks a different face).
    static func removeIfLocal(_ avatar: Avatar?) {
        guard case .photo(let url) = avatar, url.isFileURL, url.path().hasPrefix(directory.path()) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Typing "any emoji" into a text field (design §3.5): keeps the last emoji typed.
nonisolated enum EmojiInput {
    /// The last emoji grapheme in `text`, or nil if it contains none. Digits, `#` and `*` (which
    /// are technically emoji-capable) don't count unless they're keycaps.
    static func lastEmoji(in text: String) -> String? {
        text.reversed().first(where: isEmoji).map(String.init)
    }

    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        if first.properties.isEmojiPresentation { return true }
        // Text-default emoji become emoji with a variation selector or a combining sequence.
        return first.properties.isEmoji && scalars.count > 1
    }
}
