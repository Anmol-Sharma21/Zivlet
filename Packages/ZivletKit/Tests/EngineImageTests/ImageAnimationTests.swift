import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

@Suite("Animation carried: HEIC sequence → APNG, APNG → HEIC sequence (P1-08, G-5)")
struct ImageAnimationTests {
    let run = ImageRun()

    static func probe(frames: Int, type: String) -> ImageProbe {
        ImageProbe(
            typeIdentifier: type, frameCount: frames, pixelSize: ImageFixture.size, orientation: 1, hasAlpha: false)
    }

    /// The catalog has no png → png or heic → heic, so animation crosses over: HEIC sequence → APNG, APNG → HEIC
    /// sequence (and either → animated WebP, covered by the WebP writer tests).
    @Test func aHEICSequenceBecomesAnAnimatedPNG() async throws {
        let dir = try ImageFixture.directory()
        let sequence = try await offPool { try AnimationFixture.heicSequence(frames: 3, delay: 0.2, in: dir) }
        let (plan, output) = try await run.convert(sequence, .heic, to: .png, in: dir)
        #expect(plan.notes.isEmpty)
        #expect(try AnimationFixture.frameCount(output.url) == 3)
        let delays = try AnimationFixture.delays(
            output.url, family: kCGImagePropertyPNGDictionary, key: kCGImagePropertyAPNGDelayTime)
        #expect(delays == [0.2, 0.2, 0.2])
        let loop = { (url: URL, family: CFString, key: CFString) throws -> Int? in
            let file = CGImageSourceCopyProperties(try AnimationFixture.source(url), nil) as? [CFString: Any]
            return (file?[family] as? [CFString: Any])?[key] as? Int
        }
        let carried = try loop(sequence, kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSLoopCount)
        #expect(try loop(output.url, kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGLoopCount) == carried)
    }

    @Test func progressCountsFramesDone() async throws {
        let dir = try ImageFixture.directory()
        let apng = try await offPool { try AnimationFixture.animatedPNG(frames: 4, delay: 0.1, loops: 0, in: dir) }
        let seen = Mutex<[Double?]>([])
        let sink = ProgressSink(interval: .zero) { progress in seen.withLock { $0.append(progress.fraction) } }
        _ = try await run.convert(apng, .png, to: .heic, in: dir, context: ExecutionContext(progress: sink))
        #expect(seen.withLock { $0 } == [0.25, 0.5, 0.75, 1.0])
    }

    @Test func anAPNGBecomesAHEICSequence() async throws {
        let dir = try ImageFixture.directory()
        let apng = try await offPool { try AnimationFixture.animatedPNG(frames: 3, delay: 0.25, loops: 2, in: dir) }
        let (plan, output) = try await run.convert(apng, .png, to: .heic, in: dir)
        #expect(plan.notes.isEmpty && plan.stages[0].image?.destinationType == "public.heics")
        let image = try AnimationFixture.source(output.url)
        #expect(CGImageSourceGetType(image) as String? == "public.heics" && CGImageSourceGetCount(image) == 3)
        let delays = try AnimationFixture.delays(
            output.url, family: kCGImagePropertyHEICSDictionary, key: kCGImagePropertyHEICSDelayTime)
        #expect(delays == [0.25, 0.25, 0.25])
    }

    @Test(arguments: [FormatID.jpg, .tiff, .bmp, .avif])
    func otherTargetsKeepTheFirstFrameAndSaySo(target: FormatID) throws {
        let plan = try ImagePlannerTests.plan(.png, target, Self.probe(frames: 4, type: "public.png"))
        #expect(plan.stages[0].image?.frames == [0] && plan.notes == [.firstFrameOnly])
    }

    @Test func aSequenceStaysASequenceOnlyWhereImageIOCanWriteOne() throws {
        let probe = Self.probe(frames: 3, type: "public.png")
        let writable = ImageTypes.writable.union(["public.heics"])
        let sequence = try ImagePlannerTests.plan(.png, .heic, probe, writable: writable)
        #expect(sequence.stages[0].image?.frames == [0, 1, 2] && sequence.notes.isEmpty)
        let still = try ImagePlannerTests.plan(.png, .heic, probe, writable: ImageTypes.writable)
        #expect(still.stages[0].image?.destinationType == "public.heic" && still.notes == [.firstFrameOnly])
    }

    @Test func multiPageTIFFsAreNotAnimations() throws {
        let plan = try ImagePlannerTests.plan(.tiff, .png, Self.probe(frames: 3, type: "public.tiff"))
        #expect(plan.stages[0].image?.frames == [0] && plan.notes == [.firstFrameOnly])
    }

    @Test func animationsAreCappedLikeWebP() throws {
        let plan = try ImagePlannerTests.plan(.heic, .png, Self.probe(frames: 3_000, type: "public.heics"))
        #expect(plan.stages[0].image?.frames.count == ImagePlanner.maxAnimationFrames)
        #expect(plan.notes == [.firstFrameOnly])
    }
}
