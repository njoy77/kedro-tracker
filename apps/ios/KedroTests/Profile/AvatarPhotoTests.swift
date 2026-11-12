import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Kedro

@Suite("Avatars: legacy curated, crop geometry, saved photos")
struct AvatarPhotoTests {
    // MARK: Legacy curated avatars

    @Test("A curated avatar from the server decodes, any id, and re-encodes unchanged")
    func curatedRoundTrip() throws {
        for id in ["horse", "ghost", "somethingNew"] {
            let json = #"{"id":"\#(id)","kind":"curated"}"#
            let avatar = try KedroJSON.decoder().decode(Avatar.self, from: Data(json.utf8))
            #expect(avatar == .curated(id))
            let encoder = KedroJSON.encoder()
            encoder.outputFormatting = .sortedKeys
            #expect(String(decoding: try encoder.encode(avatar), as: UTF8.self) == json)
        }
    }

    @Test("A player with a curated avatar still decodes (search, directory, leaderboard)")
    func curatedPlayer() throws {
        let json = #"{"id":"6f0d6c1e-1a5b-4c55-9d43-5b1b8e0a7c11","displayName":"Ana","handle":"ana.k","avatar":{"kind":"curated","id":"spade"}}"#
        let player = try KedroJSON.decoder().decode(PlayerSummary.self, from: Data(json.utf8))
        #expect(player.avatar == .curated("spade"))
    }

    @Test("Legacy curated avatars get a stable color in the palette")
    func curatedColor() {
        for id in ["horse", "redKing", "", "spade"] {
            let index = Avatar.colorIndex(forCurated: id)
            #expect((0..<Avatar.emojiColorCount).contains(index))
            #expect(index == Avatar.colorIndex(forCurated: id))
        }
    }

    // MARK: Crop geometry

    @Test("At rest, a portrait photo crops to its centered square")
    func centeredPortrait() {
        let crop = AvatarCrop(imageSize: CGSize(width: 1000, height: 2000))
        #expect(crop.cropRect == CGRect(x: 0, y: 500, width: 1000, height: 1000))
    }

    @Test("Dragging moves the crop the other way, and stops at the photo's edge")
    func dragClamps() {
        let crop = AvatarCrop(imageSize: CGSize(width: 1000, height: 2000))
        // Drag the photo down by a quarter diameter: the crop shows higher up the photo.
        let down = crop.moved(by: CGSize(width: 0, height: 0.25))
        #expect(down.cropRect == CGRect(x: 0, y: 250, width: 1000, height: 1000))
        // Too far: the top edge stops at the top of the photo.
        let far = crop.moved(by: CGSize(width: 0, height: 5))
        #expect(far.cropRect.minY == 0)
        // Sideways there's no room at zoom 1.
        #expect(crop.moved(by: CGSize(width: 1, height: 0)).cropRect.minX == 0)
    }

    @Test("Pinching zooms about the center, within 1× and the maximum")
    func zoomClamps() {
        let crop = AvatarCrop(imageSize: CGSize(width: 2000, height: 2000))
        let zoomed = crop.zoomed(by: 2)
        #expect(zoomed.cropRect == CGRect(x: 500, y: 500, width: 1000, height: 1000))
        // Now there's room to move sideways.
        let moved = zoomed.moved(by: CGSize(width: -0.5, height: 0))
        #expect(moved.cropRect == CGRect(x: 1000, y: 500, width: 1000, height: 1000))
        // Zooming back out re-clamps so the circle stays covered.
        let out = moved.zoomed(by: 0.1)
        #expect(out.zoom == 1)
        #expect(out.cropRect == CGRect(x: 0, y: 0, width: 2000, height: 2000))
        #expect(crop.zoomed(by: 100).zoom == crop.maxZoom)
        #expect(crop.zoomed(by: .nan) == crop)
    }

    @Test("A small photo can't be zoomed into a blur")
    func smallPhotoZoom() {
        #expect(AvatarCrop(imageSize: CGSize(width: 300, height: 200)).maxZoom == 1)
        #expect(AvatarCrop(imageSize: CGSize(width: 768, height: 1024)).maxZoom == 1.5)
        // A full-zoom crop never drops under 512 px.
        let big = AvatarCrop(imageSize: CGSize(width: 3072, height: 2048)).zoomed(by: 100)
        #expect(big.cropRect.width == 512)
    }

    // MARK: Saved photo

    @Test("The saved JPEG is the chosen crop: square, at most 1024 px, under the upload limit")
    func savedPhotoMatchesCrop() throws {
        // Top half red, bottom half blue, 1200 × 2400.
        let image = try #require(Self.twoTone(width: 1200, height: 2400))
        let top = AvatarCrop(imageSize: CGSize(width: 1200, height: 2400)).moved(by: CGSize(width: 0, height: 10))
        let data = try AvatarPhotoStore.jpegData(for: image, crop: top.cropRect)
        #expect(data.count <= AvatarPhotoStore.maxBytes)

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let saved = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(saved.width == 1024)
        #expect(saved.height == 1024)
        // The crop came from the top: it's red, not blue.
        let pixel = try #require(Self.centerPixel(saved))
        #expect(pixel.red > 200)
        #expect(pixel.blue < 60)
    }

    @Test("A crop smaller than 1024 px isn't upscaled")
    func smallCrop() throws {
        let image = try #require(Self.twoTone(width: 400, height: 600))
        let crop = AvatarCrop(imageSize: CGSize(width: 400, height: 600))
        let square = try #require(AvatarPhotoStore.squareImage(image, crop: crop.cropRect))
        #expect(square.width == 400)
        #expect(square.height == 400)
    }

    private static func twoTone(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        // CGContext's origin is bottom-left: the upper half in the image is the high-y half here.
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return context.makeImage()
    }

    private static func centerPixel(_ image: CGImage) -> (red: Int, blue: Int)? {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        return (Int(bytes[0]), Int(bytes[2]))
    }
}
