import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

/// macOS 27 ImageIO writable types (13 §2.1): no WebP.
enum ImageTypes {
    static let writable: Set<String> = [
        "public.jpeg", "public.png", "public.heic", "public.tiff", "public.avif", "com.microsoft.bmp",
        "com.compuserve.gif",
    ]
}

@Suite("ImagePlanner: pure plans for raster pairs (P1-08, P1-10, 03b §6.2)")
struct ImagePlannerTests {
    static func probe(
        _ w: Int = 40, _ h: Int = 20, frames: Int = 1, orientation: Int = 1, alpha: Bool = false
    ) -> ImageProbe {
        ImageProbe(
            typeIdentifier: "public.png", frameCount: frames, pixelSize: PixelSize(width: w, height: h),
            orientation: orientation, hasAlpha: alpha)
    }

    static func plan(
        _ source: FormatID, _ target: FormatID, _ probe: ImageProbe = probe(), tier: QualityTier = .standard,
        writable: Set<String> = ImageTypes.writable
    ) throws(JobError) -> ExecutionPlan {
        let input = try InputItem(url: URL(fileURLWithPath: "/in/a.\(source.rawValue)"), format: source, byteCount: 1)
        let request = try JobRequest(
            input: input, operation: .convert(target), destination: URL(fileURLWithPath: "/in"))
        return try ImagePlanner.plan(
            request, probe: probe, staged: URL(fileURLWithPath: "/in/.zivlet-1.\(target.rawValue)"),
            writableTypes: writable, options: ImageOptions(tier: tier))
    }

    static func spec(_ plan: ExecutionPlan) throws -> ImagePipelineSpec { try #require(plan.stages.first?.image) }

    @Test(arguments: [
        (FormatID.jpg, QualityTier.small, 0.65), (.jpg, .standard, 0.85), (.heic, .best, 0.96),
        (.avif, .standard, 0.85),
    ])
    func lossyTargetsUseTheTierQuality(target: FormatID, tier: QualityTier, quality: Double) throws {
        #expect(try Self.spec(Self.plan(.png, target, tier: tier)).quality == quality)
    }

    @Test(arguments: [FormatID.png, .tiff, .bmp, .pdf])
    func losslessTargetsHaveNoQuality(target: FormatID) throws {
        let spec = try Self.spec(Self.plan(.jpg, target))
        #expect(spec.quality == nil)
        #expect(spec.tiffLZW == (target == .tiff))
        #expect(spec.output == (target == .pdf ? .pdf : .raster))
    }

    @Test(arguments: [(FormatID.jpg, true), (.bmp, true), (.png, false), (.heic, false), (.pdf, false)])
    func alphaIsFlattenedOnlyForOpaqueTargets(target: FormatID, flattens: Bool) throws {
        let plan = try Self.plan(.png == target ? .tiff : .png, target, Self.probe(alpha: true))
        #expect(try Self.spec(plan).flattenAlpha == flattens)
        #expect(plan.notes.contains(.alphaFlattened) == flattens)
    }

    @Test func opaqueSourcesAreNotFlattened() throws {
        let plan = try Self.plan(.png, .jpg, Self.probe(alpha: false))
        #expect(try !Self.spec(plan).flattenAlpha && plan.notes.isEmpty)
    }

    @Test func aMultiPageTIFFBecomesAMultiPagePDF() throws {
        let plan = try Self.plan(.tiff, .pdf, Self.probe(frames: 3))
        #expect(try Self.spec(plan).frames == [0, 1, 2] && plan.notes.isEmpty)
    }

    @Test(arguments: [(FormatID.tiff, FormatID.png), (.webp, .jpg), (.png, .pdf), (.heic, .tiff)])
    func otherMultiFrameSourcesKeepTheFirstFrameAndSaySo(source: FormatID, target: FormatID) throws {
        let plan = try Self.plan(source, target, Self.probe(frames: 4))
        #expect(try Self.spec(plan).frames == [0])
        #expect(plan.notes == [.firstFrameOnly])
    }

    @Test(arguments: [
        (6, PixelSize(width: 20, height: 40)), (3, PixelSize(width: 40, height: 20)),
        (8, PixelSize(width: 20, height: 40)),
    ])
    func theExpectedSizeIsTheDisplayedSize(orientation: Int, size: PixelSize) throws {
        #expect(try Self.spec(Self.plan(.jpg, .png, Self.probe(orientation: orientation))).expectedSize == size)
    }

    @Test func invalidOrientationsCountAsUpright() {
        #expect(Self.probe(orientation: 0).orientation == 1 && Self.probe(orientation: 9).orientation == 1)
    }

    @Test func anUnwritableTypeIsUnavailable() {
        let noAVIF = ImageTypes.writable.subtracting(["public.avif"])
        #expect(throws: JobError.routeUnavailable(.jpg, .avif, ["ImageIO public.avif encoder"])) {
            try Self.plan(.jpg, .avif, writable: noAVIF)
        }
    }

    @Test(arguments: [(20_000, 10_001), (Int.max, 2)])
    func hugeImagesAreRefusedBeforeDecoding(w: Int, h: Int) {
        #expect(throws: JobError.unsupportedInput(.tooLarge)) { try Self.plan(.png, .jpg, Self.probe(w, h)) }
    }

    @Test func emptyImagesAreUnreadable() {
        #expect(throws: JobError.unsupportedInput(.unreadable)) { try Self.plan(.png, .jpg, Self.probe(0, 10)) }
    }

    @Test func plansRunOnTheCPULane() throws {
        let plan = try Self.plan(.heic, .jpg)
        #expect(plan.engine == .image && plan.lanes == [.cpu] && plan.stageWeights == [1])
        #expect(try Self.spec(plan).destinationType == "public.jpeg")
    }

    static let imagePairs = ConversionCatalog.standard.pairs.filter {
        [.raster, .svg].contains(FormatRegistry.standard.format($0.source).category)
    }

    @Test func thereAre49RasterAnd8SVGPairs() {
        #expect(Self.imagePairs.count == 57)
        #expect(Self.imagePairs.filter { $0.source == .svg }.count == 8)
    }

    @Test(arguments: imagePairs)
    func everyImagePairPlans(pair: ConversionPair) {
        do {
            let plan = try Self.plan(pair.source, pair.target)
            #expect(plan.outputFormat == pair.target)
        } catch {
            Issue.record("\(pair): \(error)")
        }
    }
}
