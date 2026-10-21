import CoreGraphics
import EngineImage
import EngineMedia
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

extension ConversionService {
    /// Snapshots of `batch` until it finishes.
    func snapshots(until batch: BatchID) async -> [BatchSnapshot] {
        var seen: [BatchSnapshot] = []
        for await snapshot in snapshots where snapshot.batch == batch {
            seen.append(snapshot)
            if snapshot.isFinished { break }
        }
        return seen
    }
}

@Suite("ConversionService: drops in, batch snapshots out (P1-33)")
struct ConversionServiceTests {
    static func service(_ engine: FakeEngine = FakeEngine(), box: Sandbox) -> ConversionService {
        let scheduler = JobScheduler(engines: [engine], lanes: .standard(performanceCores: 2), records: nil)
        return ConversionService(scheduler: scheduler, factory: JobRequestFactory(fallbackFolder: box.dir))
    }

    @Test func retryResubmitsOnlyTheFailedItemsToTheSameTarget() async throws {
        let box = try Sandbox()
        let urls = [try box.file("a.heic"), try box.file("c.mp3")]
        let service = Self.service(box: box)
        let batch = await service.convert(urls, to: .jpg)
        _ = await service.snapshots(until: batch)
        let retried = try #require(await service.retry(batch))
        let last = try #require(await service.snapshots(until: retried).last)
        #expect(retried != batch && last.target == .jpg && last.items.map(\.name) == ["c.mp3"])
        #expect(await service.retry(BatchID()) == nil)
    }

    @Test func aBatchWithNothingFailedCannotBeRetried() async throws {
        let box = try Sandbox()
        let service = Self.service(box: box)
        let batch = await service.convert([try box.file("a.heic")], to: .jpg)
        _ = await service.snapshots(until: batch)
        #expect(await service.retry(batch) == nil)
    }

    @Test func aDropEndsInAFinishedSnapshotWithOutputsAndRefusals() async throws {
        let box = try Sandbox()
        let urls = [try box.file("a.heic"), try box.file("b.heic"), try box.file("c.mp3")]
        let service = Self.service(box: box)
        let batch = await service.convert(urls, to: .jpg)
        let snapshots = await service.snapshots(until: batch)
        let last = try #require(snapshots.last)
        #expect(last.isFinished && last.outputs.map(\.url.lastPathComponent).sorted() == ["a.jpg", "b.jpg"])
        #expect(last.failures.map(\.name) == ["c.mp3"])
        let fractions = snapshots.map(\.fraction)
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func aDropOfOnlyRefusedItemsStillFinishes() async throws {
        let box = try Sandbox()
        let service = Self.service(box: box)
        let batch = await service.convert([try box.file("notes.xyz")], to: .png)
        let last = try #require(await service.snapshots(until: batch).last)
        #expect(last.isFinished && last.failures.map(\.error) == [.unsupportedInput(.unknownFormat)])
    }

    @Test func cancellingABatchCancelsItsJobs() async throws {
        let box = try Sandbox()
        let service = Self.service(FakeEngine(body: FakeEngine.waitsForCancel), box: box)
        let batch = await service.convert([try box.file("a.heic")], to: .png)
        await service.cancel(batch)
        let last = try #require(await service.snapshots(until: batch).last)
        #expect(last.cancelledCount == 1)
        #expect(await service.shutdown(within: .seconds(2)))
        #expect(box.listing == ["a.heic"])
    }

    @Test func demoArgumentsParse() throws {
        let parsed = try DemoConversion.parse(arguments: ["Zivlet", "-ZivletDemoConvert", "/tmp/a.wav", "MP3"])
        #expect(parsed == DemoConversion(url: URL(fileURLWithPath: "/tmp/a.wav"), target: .mp3, cancelAfter: nil))
        let jpeg = try DemoConversion.parse(
            arguments: ["-ZivletDemoConvert", "/tmp/a.png", "jpeg", "-ZivletDemoCancelAfter", "250"])
        #expect(jpeg?.target == .jpg && jpeg?.cancelAfter == .milliseconds(250))
        #expect(try DemoConversion.parse(arguments: ["Zivlet"]) == nil)
    }

    @Test(arguments: [
        (["-ZivletDemoConvert", "/tmp/a.png"], DemoConversionError.missingValue("-ZivletDemoConvert")),
        (["-ZivletDemoConvert", "a.png", "jpg"], .notAbsolute("a.png")),
        (["-ZivletDemoConvert", "/a.png", "zzz"], .unknownFormat("zzz")),
        (["-ZivletDemoConvert", "/a.png", "jpg", "-ZivletDemoCancelAfter", "-5"], .badDelay("-5")),
        (
            ["-ZivletDemoConvert", "/a.png", "jpg", "-ZivletDemoCancelAfter"],
            .missingValue("-ZivletDemoCancelAfter")
        ),
    ])
    func badDemoArgumentsAreTyped(arguments: [String], error: DemoConversionError) {
        #expect(throws: error) { try DemoConversion.parse(arguments: arguments) }
    }
}

/// End to end with the real engines on a real folder (the M3 exit pairs). Media cases need a local ffmpeg.
@Suite("Real engines through the runtime (M3 exit pairs)")
struct RealConversionTests {
    static let hasFFmpeg = (try? EngineLocator().locateMediaTools()) != nil

    static func service(_ box: Sandbox) -> ConversionService {
        let scheduler = JobScheduler(engines: [ImageEngine(), MediaEngine()], records: nil)
        return ConversionService(scheduler: scheduler, factory: JobRequestFactory(fallbackFolder: box.dir))
    }

    @Test func jpgToPNGLandsBesideTheOriginal() async throws {
        let box = try Sandbox()
        let jpg = box.dir.appending(path: "Sunset.jpg")
        try await RealMedia.drawJPEG(to: jpg)
        let service = Self.service(box)
        let last = try #require(await service.snapshots(until: await service.convert([jpg], to: .png)).last)
        #expect(last.outputs.map(\.url.lastPathComponent) == ["Sunset.png"], "\(last.failures)")
        #expect(box.listing == ["Sunset.jpg", "Sunset.png"])
    }

    @Test(.enabled(if: hasFFmpeg), arguments: [(FormatID.wav, FormatID.mp3), (.mov, .mp4), (.mp4, .webm)])
    func mediaPairsLandBesideTheOriginal(source: FormatID, target: FormatID) async throws {
        let box = try Sandbox()
        let input = try await RealMedia.synthesize(source, seconds: 1, in: box.dir)
        let service = Self.service(box)
        let last = try #require(await service.snapshots(until: await service.convert([input], to: target)).last)
        #expect(last.outputs.map(\.url.lastPathComponent) == ["clip.\(target.rawValue)"], "\(last.failures)")
        #expect(!box.listing.contains { $0.hasPrefix(Publisher.stagingPrefix) })
    }

    @Test(.enabled(if: hasFFmpeg)) func cancellingALongEncodeLeavesNoPartialFile() async throws {
        let box = try Sandbox()
        let input = try await RealMedia.synthesize(.mov, seconds: 30, in: box.dir)
        let service = Self.service(box)
        let batch = await service.convert([input], to: .webm)
        var iterator = service.snapshots.makeAsyncIterator()
        while let snapshot = await iterator.next(), !(snapshot.current?.item.state.isRunning ?? false) {}
        try await Task.sleep(for: .milliseconds(300))
        await service.cancel(batch)
        while let snapshot = await iterator.next(), !snapshot.isFinished {}
        #expect(await service.shutdown(within: .seconds(2)))
        #expect(box.listing == ["clip.mov"])
    }
}

extension JobState {
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

enum RealMedia {
    static func synthesize(_ format: FormatID, seconds: Int, in dir: URL) async throws -> URL {
        let tools = try EngineLocator().locateMediaTools()
        let url = dir.appending(path: "clip.\(format.rawValue)")
        let video = ["-f", "lavfi", "-i", "testsrc2=d=\(seconds):s=1280x720:r=30"]
        let tone = ["-f", "lavfi", "-i", "sine=d=\(seconds)"]
        let codecs =
            format == .wav ? ["-c:a", "pcm_s16le"] : ["-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac"]
        let inputs = format == .wav ? tone : video + tone
        let request = SubprocessRequest(
            executable: tools.ffmpeg,
            arguments: ["-hide_banner", "-loglevel", "error", "-y"] + inputs + codecs + [url.path])
        let result = try await SubprocessRunner().run(request)
        try #require(result.termination == .exited(0), "\(result.stderrTail)")
        return url
    }

    /// A 64 × 48 JPEG drawn with Core Graphics, written off the cooperative pool.
    static func drawJPEG(to url: URL) async throws {
        try await BlockingWork.run { _ throws(JobError) in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { throw .internalInvariant("no bitmap context") }
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
            guard let image = context.makeImage(),
                let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
            else { throw .internalInvariant("no JPEG destination") }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw .internalInvariant("JPEG not written") }
        }
    }
}
