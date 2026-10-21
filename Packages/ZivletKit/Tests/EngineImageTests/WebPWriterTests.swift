import CWebP
import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

@Suite("WebP writer on real files (P1-25)")
struct WebPWriterTests {
    let run = ImageRun()

    static func convert(
        _ make: @escaping @Sendable (URL) throws -> URL, _ format: FormatID, run: ImageRun = ImageRun()
    ) async throws -> (plan: ExecutionPlan, output: URL) {
        let dir = try ImageFixture.directory()
        let source = try await offPool { try make(dir) }
        let (plan, output) = try await run.convert(source, format, to: .webp, in: dir)
        return (plan, output.url)
    }

    @Test(arguments: [FormatID.jpg, .png, .heic, .tiff, .avif, .bmp])
    func everyRasterSourceBecomesAReadableWebP(source: FormatID) async throws {
        let (_, output) = try await Self.convert({ try ImageFixture.opaque(source, in: $0) }, source)
        let image = try AnimationFixture.source(output)
        #expect(CGImageSourceGetType(image) as String? == "org.webmproject.webp")
        #expect(CGImageSourceGetCount(image) == 1)
        #expect(try ImageReader.probe(output).pixelSize == ImageFixture.size)
        #expect(try ImageFixture.pixel(output, x: 5, y: 10)[0] > 200)
        #expect(try ImageFixture.pixel(output, x: 35, y: 10)[2] > 200)
        #expect(try ImageFixture.properties(output)[kCGImagePropertyHasAlpha] as? Bool != true)
    }

    @Test func pngAlphaSurvives() async throws {
        let (plan, output) = try await Self.convert({ try ImageFixture.alphaPNG(in: $0) }, .png)
        #expect(plan.notes.isEmpty)
        #expect(try ImageFixture.properties(output)[kCGImagePropertyHasAlpha] as? Bool == true)
        #expect(try ImageFixture.pixel(output, x: 5, y: 10) == [0, 0, 0])
        #expect(try ImageFixture.pixel(output, x: 35, y: 10)[2] > 200)
    }

    @Test func animatedPNGKeepsItsFramesDelaysAndLoopCount() async throws {
        let (plan, output) = try await Self.convert(
            { try AnimationFixture.animatedPNG(frames: 4, delay: 0.1, loops: 3, in: $0) }, .png)
        #expect(plan.notes.isEmpty)
        #expect(try AnimationFixture.frameCount(output) == 4)
        #expect(try AnimationFixture.webpDelays(output) == [0.1, 0.1, 0.1, 0.1])
        #expect(try AnimationFixture.webpLoopCount(output) == 3)
    }

    @Test func iccProfileIsCarried() async throws {
        let (_, output) = try await Self.convert(
            { dir in
                let url = dir.appending(path: "p3.jpg")
                let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
                try ImageFixture.write([ImageFixture.draw(space: p3)], as: .jpg, to: url)
                return url
            }, .jpg)
        #expect((try ImageFixture.properties(output)[kCGImagePropertyProfileName] as? String)?.contains("P3") == true)
    }

    @Test func exifIsCarriedWithTheOutputSize() async throws {
        let (_, output) = try await Self.convert({ try ImageFixture.rotatedJPEG(in: $0) }, .jpg)
        let exif = try ImageFixture.properties(output)[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifPixelXDimension] as? Int == 20)
        #expect(exif?[kCGImagePropertyExifPixelYDimension] as? Int == 40)
        let dated = try await Self.convert({ try ImageFixture.opaque(.jpg, in: $0) }, .jpg)
        let date = try ImageFixture.properties(dated.output)[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(date?[kCGImagePropertyExifDateTimeOriginal] as? String == ImageFixture.date)
    }

    @Test(arguments: [2, 6])
    func orientationIsBakedAndWrittenAsOne(orientation: Int) async throws {
        let (_, output) = try await Self.convert({ try ImageOrientationTests.source(orientation, in: $0) }, .jpg)
        try ImageOrientationTests.expectBaked(output, "webp o\(orientation)")
        try ImageOrientationTests.expectColours(
            output, ImageOrientationTests.displayed, ImageOrientationTests.colours, "webp o\(orientation)")
    }

    @Test func cancellingBetweenFramesLeavesNoOutput() async throws {
        let dir = try ImageFixture.directory()
        let apng = try await offPool {
            try AnimationFixture.animatedPNG(
                frames: 120, delay: 0.04, size: PixelSize(width: 640, height: 480), in: dir)
        }
        let task = Task { try await run.convert(apng, .png, to: .webp, in: dir) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await #expect(throws: JobError.cancelled) { try await task.value }
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".zivlet-") }
        #expect(left.isEmpty)
    }

    @Test func aCancelledFlagStopsBeforeTheFirstFrame() throws {
        let dir = try ImageFixture.directory()
        let spec = try Self.spec(ImageFixture.opaque(.png, in: dir))
        let flag = CancellationFlag()
        flag.cancel()
        let staged = dir.appending(path: ".zivlet-x.webp")
        #expect(throws: JobError.cancelled) { try ImagePipeline.run(spec, to: staged, cancel: flag) }
        #expect(!FileManager.default.fileExists(atPath: staged.path))
    }

    @Test func aStagedPathSwappedForASymlinkIsNotWrittenThrough() throws {
        let dir = try ImageFixture.directory()
        let spec = try Self.spec(ImageFixture.opaque(.png, in: dir))
        let victim = dir.appending(path: "victim.txt")
        try Data("keep".utf8).write(to: victim)
        let staged = dir.appending(path: ".zivlet-x.webp")
        try FileManager.default.createSymbolicLink(at: staged, withDestinationURL: victim)
        #expect(throws: JobError.verificationFailed(StagedFile.replacedMessage)) {
            try ImagePipeline.run(spec, to: staged, cancel: CancellationFlag())
        }
        #expect(try Data(contentsOf: victim) == Data("keep".utf8))
    }

    @Test(arguments: [
        (VP8_ENC_ERROR_OUT_OF_MEMORY, JobError.writeFailed(WebPEncodeFailure.outOfMemory)),
        (VP8_ENC_ERROR_BAD_DIMENSION, .unsupportedInput(.tooLarge)),
        (VP8_ENC_ERROR_BAD_WRITE, .writeFailed("The WebP encoder stopped with error 8.")),
    ])
    func encoderErrorsAreTyped(code: WebPEncodingError, error: JobError) {
        #expect(WebPEncodeFailure.error(code) == error)
    }

    @Test func verificationRefusesTransparencyTheSourceDidNotHave() async throws {
        let (_, output) = try await Self.convert({ try ImageFixture.alphaPNG(in: $0) }, .png)
        let opaque = try Self.spec(output, alpha: false)
        #expect(throws: JobError.verificationFailed(ImageVerifier.unexpectedAlpha)) {
            try ImageVerifier.check(output, spec: opaque)
        }
    }

    @Test(arguments: [
        [UInt8](), [0xFF, 0xD8], [0x89, 0x50], [0xFF, 0xD8, 0xFF, 0xDA, 0, 4, 0, 0], [0xFF, 0xD8, 0xFF, 0xE1, 0, 99],
        [0xFF, 0xD8, 0xFF, 0xE1, 0, 1],
    ])
    func malformedJPEGsHoldNoEXIFBlock(bytes: [UInt8]) {
        #expect(EXIFBlock.segment(bytes) == nil)
    }

    @Test func theEXIFBlockIsTheAPP1PayloadAfterItsHeader() {
        let app0: [UInt8] = [0xFF, 0xE0, 0, 4, 1, 2]
        let app1: [UInt8] = [0xFF, 0xE1, 0, 10] + EXIFBlock.header + [0x4D, 0x4D]
        #expect(EXIFBlock.segment([0xFF, 0xD8] + app0 + app1) == Data([0x4D, 0x4D]))
    }

    @Test func framesWithoutTimingGetTheDefaultDuration() throws {
        let dir = try ImageFixture.directory()
        let source = try AnimationFixture.source(try ImageFixture.pagedTIFF(2, in: dir))
        let timing = WebPTiming.read(source, frames: [0, 1])
        #expect(timing == WebPTiming(durations: [100, 100], loopCount: 0))
        #expect(timing.duration(at: 5) == WebPTiming.defaultMillis)
    }

    static func spec(_ source: URL, alpha: Bool? = nil) throws -> ImagePipelineSpec {
        let probe = try ImageReader.probe(source)
        let options = WebPPlanner.options(
            tier: .standard,
            probe: ImageProbe(
                typeIdentifier: probe.typeIdentifier, frameCount: 1, pixelSize: probe.pixelSize, orientation: 1,
                hasAlpha: alpha ?? probe.hasAlpha))
        return try ImagePipelineSpec(
            source: source, destinationType: "org.webmproject.webp", output: .raster, frames: [0], flattenAlpha: false,
            quality: nil, tiffLZW: false, expectedSize: ImageFixture.size, webp: options)
    }
}
