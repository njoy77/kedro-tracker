import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Keeps avatar photos on this phone: decodes a picked or captured image for the crop editor,
/// crops it to the square the player chose, downsizes it, and writes a JPEG to Application
/// Support. The resulting `file://` URL is a valid `Avatar.photo` until `AccountSync` uploads it
/// and swaps in the remote URL.
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

    /// Pixel size of the stored square: sharp in the full-screen viewer, small enough to upload.
    static let pixelSize = 1024

    /// The API refuses photos over 512 KB (`MAX_PHOTO_BYTES` in packages/shared); stay under it.
    static let maxBytes = 500 * 1024

    /// The long side of the image the crop editor works on: a 12 MP photo keeps 2304 px on its
    /// short side, so a full-size crop is 1024 px up to about 2× zoom.
    static let editingPixelSize = 3072

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Avatars", directoryHint: .isDirectory)
    }

    /// Decodes image data for the crop editor: EXIF orientation applied (so it is upright) and
    /// the long side at most `maxPixel`.
    static func editableImage(from data: Data, maxPixel: Int = editingPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Crops `image` to `crop` (pixels, top-left origin; `AvatarCrop.cropRect`), downsizes it to
    /// at most `pixelSize` square, and saves it. Returns the file URL for `Avatar.photo`.
    static func save(_ image: CGImage, crop: CGRect) throws -> URL {
        let jpeg = try jpegData(for: image, crop: crop)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString.lowercased()).jpg")
        do {
            try jpeg.write(to: url, options: .atomic)
        } catch {
            throw PhotoError.couldNotSave
        }
        return url
    }

    /// The cropped, downsized square as JPEG, under `maxBytes`.
    static func jpegData(for image: CGImage, crop: CGRect) throws -> Data {
        guard let square = squareImage(image, crop: crop) else { throw PhotoError.unreadableImage }
        for quality in [0.85, 0.75, 0.6, 0.45] {
            guard let data = encodeJPEG(square, quality: quality) else { throw PhotoError.couldNotSave }
            if data.count <= maxBytes { return data }
        }
        throw PhotoError.couldNotSave
    }

    /// The crop, redrawn as a square of at most `pixelSize`.
    static func squareImage(_ image: CGImage, crop: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = crop.integral.intersection(bounds)
        guard !rect.isNull, rect.width >= 1, rect.height >= 1, let cropped = image.cropping(to: rect) else { return nil }
        let side = min(pixelSize, Int(min(rect.width, rect.height)))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Deletes a stored local photo (when the player picks a different face).
    static func removeIfLocal(_ avatar: Avatar?) {
        guard case .photo(let url) = avatar, url.isFileURL, url.path().hasPrefix(directory.path()) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
