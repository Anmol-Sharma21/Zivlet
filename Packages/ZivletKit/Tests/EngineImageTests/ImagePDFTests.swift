import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

/// Images → PDF (03b §6.2, P1-10): JPEG bytes embedded unchanged, page = image size at its DPI (72 if absent),
/// orientation applied once; a write that fails is not blamed on the input.
@Suite("Images into PDF: JPEG passthrough, DPI page size, orientation, write failures")
struct ImagePDFTests {
    let run = ImageRun()

    /// 40 × 20 stored pixels: top-left red, top-right blue, bottom-left green, bottom-right yellow.
    static func quadrants(orientation: Int, as format: FormatID = .jpg, dpi: Double? = nil, in dir: URL) throws -> URL {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let colours: [(CGFloat, CGFloat, CGFloat, CGRect)] = [
            (1, 0, 0, CGRect(x: 0, y: 10, width: 20, height: 10)),
            (0, 0, 1, CGRect(x: 20, y: 10, width: 20, height: 10)),
            (0, 1, 0, CGRect(x: 0, y: 0, width: 20, height: 10)), (1, 1, 0, CGRect(x: 20, y: 0, width: 20, height: 10)),
        ]
        for (r, g, b, rect) in colours {
            context.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            context.fill(rect)
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if let dpi { properties.merge([kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]) { $1 } }
        let url = dir.appending(path: "q\(orientation).\(format.rawValue)")
        try ImageFixture.write([try #require(context.makeImage())], as: format, to: url, properties: properties)
        return url
    }

    /// RGB at (x, y) from the top-left of `image`, drawn into an sRGB bitmap of its own size.
    static func rgb(_ image: CGImage, x: Int, y: Int) throws -> [Int] {
        var rgba = [UInt8](repeating: 0, count: 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return rgba.prefix(3).map(Int.init)
    }

    static func rendered(_ pdf: URL) throws -> CGImage {
        let page = try #require(CGPDFDocument(pdf as CFURL)?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: Int(box.width), height: Int(box.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.drawPDFPage(page)
        return try #require(context.makeImage())
    }

    static func displayed(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 40,
        ]
        return try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary))
    }

    @Test func aJPEGIsEmbeddedUnchangedNotReencoded() async throws {
        let dir = try ImageFixture.directory()
        let jpeg = try await offPool { try Self.quadrants(orientation: 1, in: dir) }
        let (_, output) = try await run.convert(jpeg, .jpg, to: .pdf, in: dir)
        let pdf = try Data(contentsOf: output.url)
        #expect(pdf.range(of: Data("/DCTDecode".utf8)) != nil)
        #expect(pdf.range(of: try Data(contentsOf: jpeg).suffix(64)) != nil, "the JPEG's own bytes are in the PDF")
    }

    @Test(arguments: 1...8)
    func everyOrientationIsAppliedOnce(orientation: Int) async throws {
        let dir = try ImageFixture.directory()
        let jpeg = try await offPool { try Self.quadrants(orientation: orientation, in: dir) }
        let (plan, output) = try await run.convert(jpeg, .jpg, to: .pdf, in: dir)
        let page = try Self.rendered(output.url)
        let expected = try Self.displayed(jpeg)
        #expect(page.width == expected.width && page.height == expected.height)
        #expect(plan.stages.first?.image?.expectedSize == PixelSize(width: expected.width, height: expected.height))
        for (fx, fy) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] {
            let (x, y) = (Int(Double(page.width) * fx), Int(Double(page.height) * fy))
            let got = try Self.rgb(page, x: x, y: y)
            let want = try Self.rgb(expected, x: x, y: y)
            #expect(zip(got, want).allSatisfy { abs($0 - $1) < 60 }, "o\(orientation) at \(x),\(y): \(got) vs \(want)")
        }
    }

    @Test(arguments: [FormatID.png, .jpg])
    func thePageIsTheImageSizeAtItsDPI(format: FormatID) async throws {
        let dir = try ImageFixture.directory()
        let image = try await offPool { try Self.quadrants(orientation: 1, as: format, dpi: 288, in: dir) }
        let (plan, output) = try await run.convert(image, format, to: .pdf, in: dir)
        let box = try #require(CGPDFDocument(output.url as CFURL)?.page(at: 1)).getBoxRect(.mediaBox)
        #expect(box.width == 10 && box.height == 5)
        #expect(plan.stages.first?.image?.expectedSize == PixelSize(width: 10, height: 5))
    }

    @Test(arguments: [
        (40, 20, 72.0, 72.0, 40.0, 20.0), (1200, 800, 300, 300, 288, 192), (40, 20, 0, 0, 40, 20),
        (40, 20, 144, 72, 20, 20),
    ])
    func pageSizeArithmetic(w: Int, h: Int, dx: Double, dy: Double, pw: Double, ph: Double) {
        let size = PDFPageGeometry.pageSize(display: PixelSize(width: w, height: h), dpiX: dx, dpiY: dy)
        #expect(size.width == pw && size.height == ph)
    }

    @Test(arguments: [ImageOutputKind.raster, .pdf])
    func aFailedWriteIsAWriteFailureNotAnUnreadableInput(output: ImageOutputKind) throws {
        let dir = try ImageFixture.directory()
        let source = try Self.quadrants(orientation: 1, as: .png, in: dir)
        let spec = try ImagePipelineSpec(
            source: source, destinationType: output == .pdf ? "com.adobe.pdf" : "public.png", output: output,
            frames: [0], flattenAlpha: false, quality: nil, tiffLZW: false,
            expectedSize: PixelSize(width: 40, height: 20))
        let nowhere = dir.appending(path: "missing/out")
        #expect(throws: JobError.writeFailed("The converted image could not be written.")) {
            try ImagePipeline.run(spec, to: nowhere, cancel: CancellationFlag())
        }
    }

    @Test func aWriteFailureOnANearlyFullVolumeIsDiskFull() {
        #expect(ImageWriteFailure.error(freeBytes: 1_024) == .diskFull)
        #expect(ImageWriteFailure.error(freeBytes: nil) == .writeFailed("The converted image could not be written."))
        #expect(
            ImageWriteFailure.error(freeBytes: 10 << 30) == .writeFailed("The converted image could not be written."))
    }
}
