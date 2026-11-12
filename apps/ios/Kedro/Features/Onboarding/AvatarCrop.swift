import CoreGraphics

/// Where the photo sits under the round crop in `AvatarCropView`, independent of screen size.
///
/// The circle's diameter is the unit. At `zoom` 1 the image's short side exactly fills the circle;
/// `offset` is how far the image's center sits from the circle's center, in diameters. Every
/// change is clamped so the circle is always fully covered by the image.
nonisolated struct AvatarCrop: Hashable, Sendable {
    /// The image's size in pixels (already upright).
    var imageSize: CGSize
    private(set) var zoom: CGFloat = 1
    private(set) var offset: CGSize = .zero

    /// The smallest square the crop may shrink to, so a zoomed-in photo stays sharp enough for
    /// the full-screen viewer.
    static let minimumCropPixels: CGFloat = 512

    /// The closest crop: 4×, or a `minimumCropPixels` square, whichever is wider.
    var maxZoom: CGFloat { max(1, min(4, shortSide / Self.minimumCropPixels)) }

    init(imageSize: CGSize) {
        self.imageSize = CGSize(width: max(1, imageSize.width), height: max(1, imageSize.height))
    }

    private var shortSide: CGFloat { min(imageSize.width, imageSize.height) }

    /// The image's displayed size, in diameters.
    var displayedSize: CGSize {
        CGSize(width: imageSize.width / shortSide * zoom, height: imageSize.height / shortSide * zoom)
    }

    /// Moves the image by `delta` diameters (a drag), as far as the circle stays covered.
    func moved(by delta: CGSize) -> AvatarCrop {
        var copy = self
        copy.offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
        copy.clampOffset()
        return copy
    }

    /// Zooms by `factor` (a pinch) about the circle's center, within 1…`maxZoom`.
    func zoomed(by factor: CGFloat) -> AvatarCrop {
        guard factor.isFinite, factor > 0 else { return self }
        var copy = self
        copy.zoom = min(maxZoom, max(1, zoom * factor))
        let applied = copy.zoom / zoom
        copy.offset = CGSize(width: offset.width * applied, height: offset.height * applied)
        copy.clampOffset()
        return copy
    }

    /// The square of the image inside the circle, in pixels with a top-left origin (what
    /// `CGImage.cropping(to:)` takes).
    var cropRect: CGRect {
        let side = shortSide / zoom
        let center = CGPoint(
            x: imageSize.width / 2 - offset.width * side,
            y: imageSize.height / 2 - offset.height * side
        )
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    private mutating func clampOffset() {
        let size = displayedSize
        let maxX = max(0, (size.width - 1) / 2)
        let maxY = max(0, (size.height - 1) / 2)
        offset = CGSize(width: min(maxX, max(-maxX, offset.width)), height: min(maxY, max(-maxY, offset.height)))
    }
}
