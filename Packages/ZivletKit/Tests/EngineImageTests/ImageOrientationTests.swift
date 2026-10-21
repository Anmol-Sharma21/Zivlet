import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

/// The EXIF orientation tag is baked into the pixels for targets whose viewers often ignore it (PNG, BMP, GIF) or
/// whose ImageIO encoder drops it (AVIF), and kept, with the stored pixels copied, where it is well supported (JPEG,
/// HEIC, TIFF). 03b §6.1, D-M3-29.
@Suite("Orientation: baked into pixels for PNG/BMP/GIF/AVIF, tag kept for JPEG/HEIC/TIFF")
struct ImageOrientationTests {
    let run = ImageRun()

    /// The displayed picture every source shows once its orientation is applied: 40 × 20, top-left red, top-right
    /// blue, bottom-left green, bottom-right yellow. Corners are indexed top-left, top-right, bottom-left,
    /// bottom-right.
    static let displayed = PixelSize(width: 40, height: 20)
    static let colours: [[UInt8]] = [[255, 0, 0], [0, 0, 255], [0, 255, 0], [255, 255, 0]]

    /// For each EXIF orientation (1…8), the displayed corner that each stored corner lands on (EXIF 2.32 §4.6.4,
    /// written out by hand so the oracle does not depend on ImageIO).
    static let landsOn: [Int: [Int]] = [
        1: [0, 1, 2, 3], 2: [1, 0, 3, 2], 3: [3, 2, 1, 0], 4: [2, 3, 0, 1],
        5: [0, 2, 1, 3], 6: [1, 3, 0, 2], 7: [3, 1, 2, 0], 8: [2, 0, 3, 1],
    ]

    static func storedSize(_ orientation: Int) -> PixelSize {
        orientation >= 5 ? PixelSize(width: displayed.height, height: displayed.width) : displayed
    }

    /// The colour stored in each corner, so that applying `orientation` shows the displayed picture.
    static func storedColours(_ orientation: Int) throws -> [[UInt8]] {
        try #require(landsOn[orientation]).map { colours[$0] }
    }

    /// The centre of each quadrant (top-left, top-right, bottom-left, bottom-right), from the top-left.
    static func centres(_ size: PixelSize) -> [(x: Int, y: Int)] {
        let (w, h) = (size.width, size.height)
        return [(w / 4, h / 4), (w * 3 / 4, h / 4), (w / 4, h * 3 / 4), (w * 3 / 4, h * 3 / 4)]
    }

    /// An image (JPEG unless told otherwise) whose stored quadrants are laid out so that `orientation` displays the
    /// canonical picture.
    static func source(_ orientation: Int, as format: FormatID = .jpg, in dir: URL) throws -> URL {
        let size = storedSize(orientation)
        let space = try #require(ImageFixture.srgb)
        let context = try #require(
            CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let (hw, hh) = (size.width / 2, size.height / 2)
        let origins = [(0, hh), (hw, hh), (0, 0), (hw, 0)]  // Quartz: origin bottom left.
        for (colour, origin) in zip(try storedColours(orientation), origins) {
            let rgb = colour.map { CGFloat($0) / 255 }
            context.setFillColor(CGColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1))
            context.fill(CGRect(x: origin.0, y: origin.1, width: hw, height: hh))
        }
        let url = dir.appending(path: "o\(orientation).\(format.rawValue)")
        try ImageFixture.write(
            [try #require(context.makeImage())], as: format, to: url,
            properties: [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 1.0])
        return url
    }

    static func expectColours(_ url: URL, _ size: PixelSize, _ want: [[UInt8]], _ label: String) throws {
        for (centre, colour) in zip(centres(size), want) {
            let got = try ImageFixture.pixel(url, x: centre.x, y: centre.y)
            let close = zip(got, colour).allSatisfy { abs(Int($0) - Int($1)) < 60 }
            #expect(close, "\(label) at \(centre): \(got), want \(colour)")
        }
    }

    /// Stored pixels upright, orientation 1 (or absent), stored size = displayed size.
    static func expectBaked(_ url: URL, _ label: String) throws {
        let probe = try ImageReader.probe(url)
        #expect(probe.orientation == 1, "\(label): \(probe)")
        #expect(probe.pixelSize == displayed, "\(label): \(probe)")
        try expectColours(url, displayed, colours, label)
    }

    /// AVIF: ImageIO writes no `irot`/`imir`, so a kept tag would silently be lost (macOS 27).
    @Test(arguments: [FormatID.png, .bmp, .avif], 1...8)
    func weakTagTargetsGetTheOrientationBakedIn(target: FormatID, orientation: Int) async throws {
        let dir = try ImageFixture.directory()
        let input = try await offPool { try Self.source(orientation, in: dir) }
        let (plan, output) = try await run.convert(input, .jpg, to: target, in: dir)
        #expect(plan.stages.first?.image?.expectedSize == Self.displayed)
        try Self.expectBaked(output.url, "\(target) o\(orientation)")
    }

    /// GIF output is a media-engine route; the pipeline still bakes for it when handed a GIF destination.
    @Test(arguments: 1...8)
    func gifGetsTheOrientationBakedIn(orientation: Int) async throws {
        let dir = try ImageFixture.directory()
        let input = try await offPool { try Self.source(orientation, in: dir) }
        let spec = try ImagePipelineSpec(
            source: input, destinationType: "com.compuserve.gif", output: .raster, frames: [0], flattenAlpha: false,
            quality: nil, tiffLZW: false, expectedSize: Self.displayed)
        let staged = dir.appending(path: "out.gif")
        try await offPool { try ImagePipeline.run(spec, to: staged, cancel: CancellationFlag()) }
        try Self.expectBaked(staged, "gif o\(orientation)")
    }

    /// JPEG → JPEG is not a conversion, so the JPEG target is fed a TIFF.
    @Test(arguments: [FormatID.jpg, .heic, .tiff], 1...8)
    func wellSupportedTargetsKeepTheTagAndTheStoredPixels(target: FormatID, orientation: Int) async throws {
        let dir = try ImageFixture.directory()
        let format: FormatID = target == .jpg ? .tiff : .jpg
        let input = try await offPool { try Self.source(orientation, as: format, in: dir) }
        let (_, output) = try await run.convert(input, format, to: target, in: dir)
        let probe = try ImageReader.probe(output.url)
        let label = "\(target) o\(orientation)"
        #expect(probe.orientation == orientation, "\(label): \(probe)")
        #expect(probe.pixelSize == Self.storedSize(orientation), "\(label): \(probe)")
        #expect(probe.displaySize == Self.displayed, "\(label): \(probe)")
        try Self.expectColours(output.url, Self.storedSize(orientation), try Self.storedColours(orientation), label)
    }

    @Test func aBakedFrameCarriesItsOtherMetadata() async throws {
        let dir = try ImageFixture.directory()
        let input = dir.appending(path: "dated.jpg")
        try await offPool {
            try ImageFixture.write(
                [try ImageFixture.draw(space: try #require(ImageFixture.srgb))], as: .jpg, to: input,
                properties: [
                    kCGImagePropertyOrientation: 6,
                    kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: ImageFixture.date],
                ])
        }
        let (_, output) = try await run.convert(input, .jpg, to: .png, in: dir)
        let properties = try ImageFixture.properties(output.url)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == ImageFixture.date)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect((tiff?[kCGImagePropertyTIFFOrientation] as? Int ?? 1) == 1, "\(tiff ?? [:])")
    }

    @Test(arguments: [
        ("public.jpeg", false), ("public.heic", false), ("public.heif", false), ("public.tiff", false),
        ("public.avif", true), ("public.png", true), ("com.microsoft.bmp", true), ("com.compuserve.gif", true),
        ("org.webmproject.webp", true), ("com.example.unknown", true),
    ])
    func onlyWellSupportedTypesKeepTheTag(type: String, bakes: Bool) {
        #expect(OrientationPolicy.bakes(6, into: type) == bakes)
        #expect(!OrientationPolicy.bakes(1, into: type), "upright frames are never decoded for orientation")
        #expect(!OrientationPolicy.bakes(0, into: type) && !OrientationPolicy.bakes(9, into: type))
    }
}
