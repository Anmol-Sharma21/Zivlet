import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

@Suite("ImageEngine on real files: every raster pair, alpha, orientation, depth, CMYK, pages (P1-24)")
struct ImageEngineTests {
    let run = ImageRun()

    @Test(arguments: ImagePlannerTests.imagePairs)
    func everyPairConvertsAndVerifies(pair: ConversionPair) async throws {
        let dir = try ImageFixture.directory()
        let source = try await offPool { try ImageFixture.opaque(pair.source, in: dir) }
        let (plan, output) = try await run.convert(source, pair.source, to: pair.target, in: dir)
        #expect(output.byteCount > 0 && output.format == pair.target && plan.engine == .image)
    }

    @Test(arguments: [FormatID.jpg, .bmp])
    func transparencyIsFlattenedOntoWhite(target: FormatID) async throws {
        let dir = try ImageFixture.directory()
        let (plan, output) = try await run.convert(
            try await offPool { try ImageFixture.alphaPNG(in: dir) }, .png, to: target, in: dir)
        #expect(plan.notes == [.alphaFlattened])
        #expect(try ImageFixture.properties(output.url)[kCGImagePropertyHasAlpha] as? Bool != true)
        #expect(try ImageFixture.pixel(output.url, x: 5, y: 10).allSatisfy { $0 > 245 })
        #expect(try ImageFixture.pixel(output.url, x: 35, y: 10)[2] > 200)
    }

    @Test func transparencyIsKeptWhereTheTargetHasIt() async throws {
        let dir = try ImageFixture.directory()
        let (plan, output) = try await run.convert(
            try await offPool { try ImageFixture.alphaPNG(in: dir) }, .png, to: .tiff, in: dir)
        #expect(plan.notes.isEmpty)
        #expect(try ImageFixture.properties(output.url)[kCGImagePropertyHasAlpha] as? Bool == true)
    }

    @Test(arguments: [FormatID.png, .heic, .bmp, .tiff, .pdf])
    func orientationIsAppliedExactlyOnce(target: FormatID) async throws {
        let dir = try ImageFixture.directory()
        let (plan, output) = try await run.convert(
            try await offPool { try ImageFixture.rotatedJPEG(in: dir) }, .jpg, to: target, in: dir)
        #expect(plan.stages.first?.image?.expectedSize == PixelSize(width: 20, height: 40))
        guard target != .pdf else { return }
        let probe = try ImageReader.probe(output.url)
        #expect(probe.displaySize == PixelSize(width: 20, height: 40), "\(target): \(probe)")
    }

    @Test(arguments: [(FormatID.tiff, 16), (.heic, 10), (.avif, 10), (.jpg, 8)])
    func depthIsKeptWhereTheTargetAllowsAndTheProfileAlways(target: FormatID, depth: Int) async throws {
        let dir = try ImageFixture.directory()
        let (_, output) = try await run.convert(
            try await offPool { try ImageFixture.deepP3PNG(in: dir) }, .png, to: target, in: dir)
        let properties = try ImageFixture.properties(output.url)
        #expect(properties[kCGImagePropertyDepth] as? Int == depth)
        #expect((properties[kCGImagePropertyProfileName] as? String)?.contains("P3") == true)
    }

    @Test(arguments: [(FormatID.png, "RGB"), (.heic, "RGB"), (.tiff, "CMYK")])
    func cmykIsConvertedOnlyForTargetsWithoutIt(target: FormatID, model: String) async throws {
        let dir = try ImageFixture.directory()
        let (_, output) = try await run.convert(
            try await offPool { try ImageFixture.cmykJPEG(in: dir) }, .jpg, to: target, in: dir)
        #expect(try ImageFixture.properties(output.url)[kCGImagePropertyColorModel] as? String == model)
    }

    /// 03b §6.2: TIFF output is LZW whatever the source carries (a JPEG's own TIFF/EXIF metadata included).
    @Test(arguments: [FormatID.jpg, .png, .heic])
    func tiffOutputIsLZWCompressed(source: FormatID) async throws {
        let dir = try ImageFixture.directory()
        let input = try await offPool { try ImageFixture.opaque(source, in: dir) }
        let (_, output) = try await run.convert(input, source, to: .tiff, in: dir)
        let tiff = try ImageFixture.properties(output.url)[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFCompression] as? Int == TIFFCompression.lzw, "\(source): \(tiff ?? [:])")
    }

    @Test func aThreePageTIFFBecomesAThreePagePDF() async throws {
        let dir = try ImageFixture.directory()
        let (plan, output) = try await run.convert(
            try await offPool { try ImageFixture.pagedTIFF(3, in: dir) }, .tiff, to: .pdf, in: dir)
        #expect(plan.notes.isEmpty)
        #expect(CGPDFDocument(output.url as CFURL)?.numberOfPages == 3)
    }

    @Test func aThreePageTIFFToPNGKeepsPageOneAndSaysSo() async throws {
        let dir = try ImageFixture.directory()
        let (plan, output) = try await run.convert(
            try await offPool { try ImageFixture.pagedTIFF(3, in: dir) }, .tiff, to: .png, in: dir)
        #expect(plan.notes == [.firstFrameOnly])
        #expect(try ImageReader.probe(output.url).frameCount == 1)
    }

    @Test func metadataIsCarried() async throws {
        let dir = try ImageFixture.directory()
        let (_, output) = try await run.convert(
            try await offPool { try ImageFixture.opaque(.jpg, in: dir) }, .jpg, to: .heic, in: dir)
        let exif = try ImageFixture.properties(output.url)[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal] as? String == ImageFixture.date)
    }

    /// ImageIO itself reports no properties for a 60,000 × 60,000 header without matching pixel data, so the file is
    /// refused before any decode; the 200 MP cap for real headers is covered by `ImagePlannerTests`.
    @Test func aCraftedHugeHeaderIsRefusedBeforeDecoding() async throws {
        let dir = try ImageFixture.directory()
        let huge = try await offPool { try ImageFixture.hugePNGHeader(in: dir) }
        await #expect(throws: JobError.unsupportedInput(.unreadable)) {
            try await run.convert(huge, .png, to: .jpg, in: dir)
        }
    }

    @Test func somethingThatIsNotAnImageIsUnreadable() async throws {
        let dir = try ImageFixture.directory()
        let fake = dir.appending(path: "fake.png")
        try Data("not an image".utf8).write(to: fake)
        await #expect(throws: JobError.unsupportedInput(.unreadable)) {
            try await run.convert(fake, .png, to: .jpg, in: dir)
        }
    }
}

@Suite("ImageEngine gates and verification failures")
struct ImageEngineGateTests {
    @Test func availabilityAndHandledPairs() async {
        let engine = ImageEngine(writableTypes: ImageTypes.writable)
        #expect(await engine.availability(of: ConversionPair(source: .png, target: .jpg)) == .available)
        #expect(await engine.availability(of: ConversionPair(source: .png, target: .webp)) == .available)
        #expect(await engine.availability(of: ConversionPair(source: .svg, target: .pdf)) == .available)
        #expect(engine.handles(ConversionPair(source: .heic, target: .pdf)))
        #expect(!engine.handles(ConversionPair(source: .pdf, target: .png)))
        #expect(!engine.handles(ConversionPair(source: .mp4, target: .gif)))
        #expect(ImageEngine.systemWritableTypes().contains("public.heic"))
    }

    static func tampered(_ plan: ExecutionPlan, size: PixelSize? = nil, type: String? = nil, frames: [Int]? = nil)
        throws -> ExecutionPlan
    {
        let spec = try #require(plan.stages.first?.image)
        let changed = try ImagePipelineSpec(
            source: spec.source, destinationType: type ?? spec.destinationType, output: spec.output,
            frames: frames ?? spec.frames, flattenAlpha: spec.flattenAlpha, quality: spec.quality,
            tiffLZW: spec.tiffLZW,
            expectedSize: size ?? spec.expectedSize)
        return try ExecutionPlan(
            engine: .image, stages: [.image(changed)], stageWeights: [1], lanes: [.cpu],
            outputFormat: plan.outputFormat,
            stagedFile: plan.stagedFile)
    }

    @Test(arguments: [FormatID.png, .pdf])
    func verifyRefusesAWrongSizeTypeOrPageCount(target: FormatID) async throws {
        let dir = try ImageFixture.directory()
        let (plan, output) = try await ImageRun().convert(
            try await offPool { try ImageFixture.opaque(.jpg, in: dir) }, .jpg, to: target, in: dir)
        let engine = ImageEngine()
        let wrongSize = try Self.tampered(plan, size: PixelSize(width: 1, height: 1))
        await #expect(throws: JobError.self) { try await engine.verify(output, plan: wrongSize) }
        let wrongShape = try Self.tampered(plan, type: "public.tiff", frames: [0, 1])
        await #expect(throws: JobError.self) { try await engine.verify(output, plan: wrongShape) }
        let empty = StagedOutput(format: target, url: output.url, byteCount: 0)
        await #expect(throws: JobError.verificationFailed("The output file is empty.")) {
            try await engine.verify(empty, plan: plan)
        }
    }

    @Test func verifyRefusesARasterWithTheWrongFrameCount() async throws {
        let dir = try ImageFixture.directory()
        let (plan, output) = try await ImageRun().convert(
            try await offPool { try ImageFixture.opaque(.jpg, in: dir) }, .jpg, to: .png, in: dir)
        let twoFrames = try Self.tampered(plan, frames: [0, 1])
        await #expect(throws: JobError.verificationFailed("The output has 1 frame, expected 2.")) {
            try await ImageEngine().verify(output, plan: twoFrames)
        }
    }

    @Test func aMissingStagedFileFailsVerification() async throws {
        let dir = try ImageFixture.directory()
        let (plan, output) = try await ImageRun().convert(
            try await offPool { try ImageFixture.opaque(.png, in: dir) }, .png, to: .bmp, in: dir)
        try FileManager.default.removeItem(at: output.url)
        await #expect(throws: JobError.verificationFailed("The output could not be read back.")) {
            try await ImageEngine().verify(output, plan: plan)
        }
    }
}
