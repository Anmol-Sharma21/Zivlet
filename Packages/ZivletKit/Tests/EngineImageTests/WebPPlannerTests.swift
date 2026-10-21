import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

@Suite("WebP plan (P1-09, 03b §6.2)")
struct WebPPlannerTests {
    static func probe(alpha: Bool = false, frames: Int = 1, type: String = "public.png") -> ImageProbe {
        ImageProbe(
            typeIdentifier: type, frameCount: frames, pixelSize: PixelSize(width: 64, height: 48), orientation: 1,
            hasAlpha: alpha)
    }

    static func plan(_ source: FormatID = .png, probe: ImageProbe) throws(JobError) -> ExecutionPlan {
        let input = try InputItem(url: URL(fileURLWithPath: "/in/a.\(source.rawValue)"), format: source, byteCount: 10)
        let request = try JobRequest(input: input, operation: .convert(.webp), destination: URL(fileURLWithPath: "/in"))
        return try ImagePlanner.plan(
            request, probe: probe, staged: URL(fileURLWithPath: "/in/.s"), writableTypes: [], options: ImageOptions())
    }

    @Test(arguments: [(QualityTier.small, 65.0), (.standard, 85.0), (.best, 96.0)])
    func qualityFollowsTheLadder(tier: QualityTier, quality: Double) {
        let options = WebPPlanner.options(tier: tier, probe: Self.probe())
        #expect(options.quality == quality)
        #expect(options.method == 4 && options.sharpYUV && !options.lossless)
    }

    @Test func alphaKeepsExactRGBUnderTransparentPixels() {
        #expect(WebPPlanner.options(tier: .standard, probe: Self.probe(alpha: true)).exactAlpha)
        #expect(!WebPPlanner.options(tier: .standard, probe: Self.probe(alpha: false)).exactAlpha)
    }

    @Test(arguments: [
        ("public.png", 5, true), ("public.heics", 3, true), ("public.tiff", 4, false), ("public.png", 1, false),
    ])
    func animationIsCarriedOnlyFromAnimatedTypes(type: String, frames: Int, animated: Bool) {
        let options = WebPPlanner.options(tier: .standard, probe: Self.probe(frames: frames, type: type))
        #expect(options.animated == animated)
    }

    @Test func metadataIsKeptByDefault() {
        let options = WebPPlanner.options(tier: .standard, probe: Self.probe())
        #expect(options.keepICC && options.keepEXIF && options.keepXMP)
    }

    @Test func planForPngToWebpCarriesTheOptionsAndAllFramesWhenAnimated() throws {
        let plan = try Self.plan(probe: Self.probe(frames: 5))
        guard case .image(let spec) = plan.stages[0] else {
            Issue.record("not an image stage")
            return
        }
        #expect(spec.destinationType == "org.webmproject.webp")
        #expect(spec.webp?.animated == true && spec.frames == [0, 1, 2, 3, 4])
        #expect(spec.quality == nil && !spec.flattenAlpha)
        #expect(plan.notes.isEmpty)
    }

    @Test func aMultiPageTIFFKeepsTheFirstPageAndSaysSo() throws {
        let plan = try Self.plan(.tiff, probe: Self.probe(frames: 3, type: "public.tiff"))
        #expect(plan.stages[0].image?.frames == [0] && plan.notes == [.firstFrameOnly])
    }

    @Test func animationIsCappedByTheJobPixelBudget() throws {
        let big = ImageProbe(
            typeIdentifier: "public.png", frameCount: 50, pixelSize: PixelSize(width: 10_000, height: 10_000),
            orientation: 1, hasAlpha: false)
        let plan = try Self.plan(probe: big)
        #expect(plan.stages[0].image?.frames == Array(0..<10) && plan.notes == [.firstFrameOnly])
    }

    @Test func animationIsCappedAtAThousandFrames() {
        #expect(WebPPlanner.frames(probe: Self.probe(frames: 5_000), animated: true).count == 1_000)
        #expect(WebPPlanner.frames(probe: Self.probe(frames: 5_000), animated: false) == [0])
    }

    @Test func webpIsAvailableWithoutAnImageIOEncoder() {
        #expect(ImageRoutes.missing(source: .png, target: .webp, writableTypes: []) == nil)
    }

    @Test(arguments: [-1.0, 101.0])
    func invalidQualityIsRefusedOnDecode(quality: Double) throws {
        let json =
            #"{"quality":\#(quality),"method":4,"sharpYUV":true,"exactAlpha":false,"lossless":false,"#
            + #""animated":false,"keepICC":true,"keepEXIF":true,"keepXMP":true}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WebPOptions.self, from: Data(json.utf8)) }
    }

    @Test(arguments: [-1, 7])
    func invalidMethodIsRefused(method: Int) {
        #expect(throws: PlanError.badMethod) {
            try WebPOptions(
                quality: 85, method: method, sharpYUV: true, exactAlpha: false, lossless: false, animated: false,
                keepICC: true, keepEXIF: true, keepXMP: true)
        }
    }

    @Test func optionsRoundTripThroughTheSpec() throws {
        let plan = try Self.plan(probe: Self.probe(alpha: true, frames: 2))
        let decoded = try JSONDecoder().decode(ExecutionPlan.self, from: JSONEncoder().encode(plan))
        #expect(decoded == plan && decoded.stages[0].image?.webp?.exactAlpha == true)
    }
}
