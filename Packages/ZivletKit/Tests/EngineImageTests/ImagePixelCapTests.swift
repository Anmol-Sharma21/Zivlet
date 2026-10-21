import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

/// 10 §8.9 decode cap, enforced in the pipeline on the handle that is decoded: every frame, not only frame 0, and a
/// budget for all frames of one job. Small limits stand in for 200 MP so the fixtures stay tiny.
@Suite("Image pixel caps per frame and per job (10 §8.9)")
struct ImagePixelCapTests {
    static func tiff(sides: [Int], in dir: URL) throws -> URL {
        let url = dir.appending(path: "pages.tiff")
        let type = FormatRegistry.standard.format(.tiff).contentTypes[0] as CFString
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type, sides.count, nil))
        for side in sides {
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(
                CGContext(
                    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        }
        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    static func spec(_ url: URL, _ output: ImageOutputKind, frames: [Int]) throws -> ImagePipelineSpec {
        try ImagePipelineSpec(
            source: url, destinationType: output == .pdf ? "com.adobe.pdf" : "public.png", output: output,
            frames: frames, flattenAlpha: false, quality: nil, tiffLZW: false,
            expectedSize: PixelSize(width: 10, height: 10))
    }

    @Test(arguments: [ImageOutputKind.pdf, .raster])
    func aSmallFirstPageDoesNotAdmitAHugeLaterOne(output: ImageOutputKind) throws {
        let dir = try ImageFixture.directory()
        let url = try Self.tiff(sides: [10, 40], in: dir)
        let limits = PixelLimits(perFrame: 1_000, perJob: 100_000)
        let frames = output == .pdf ? [0, 1] : [1]
        #expect(throws: JobError.unsupportedInput(.tooLarge)) {
            try ImagePipeline.run(
                try Self.spec(url, output, frames: frames), to: dir.appending(path: "out"), cancel: CancellationFlag(),
                limits: limits)
        }
    }

    @Test func allPagesOfOneJobShareABudget() throws {
        let dir = try ImageFixture.directory()
        let url = try Self.tiff(sides: [10, 10, 10], in: dir)
        let spec = try Self.spec(url, .pdf, frames: [0, 1, 2])
        let out = dir.appending(path: "out.pdf")
        #expect(throws: JobError.unsupportedInput(.tooLarge)) {
            try ImagePipeline.run(
                spec, to: out, cancel: CancellationFlag(), limits: PixelLimits(perFrame: 100, perJob: 250))
        }
        try ImagePipeline.run(
            spec, to: out, cancel: CancellationFlag(), limits: PixelLimits(perFrame: 100, perJob: 300))
        #expect(CGPDFDocument(out as CFURL)?.numberOfPages == 3)
    }

    @Test func theStandardLimitsAreTheDecodeCap() {
        #expect(PixelLimits.standard.perFrame == ImagePlanner.maxPixels)
        #expect(PixelLimits.standard.perJob >= PixelLimits.standard.perFrame)
    }
}
