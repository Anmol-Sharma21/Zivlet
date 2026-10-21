import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

/// Plan snapshots for every raster pair under five probes (P1-08). The goldens are JSON maps "source__target" →
/// `ExecutionPlan`, one file per probe, generated once with `ZIVLET_RECORD_GOLDENS=1` and reviewed. Bit depth and
/// profile do not appear in a plan (ImageIO keeps them at execute time), so the probes vary what plans do depend on.
@Suite("Image plan goldens: 49 raster pairs × 5 probes (P1-08)")
struct ImagePlanGoldenTests {
    enum Variant: String, CaseIterable, Sendable {
        case still, alpha, animated, rotated, gainMap

        func probe(_ source: FormatID) -> ImageProbe {
            let still = FormatRegistry.standard.format(source).contentTypes[0]
            let animatedType = [FormatID.png: "public.png", .heic: "public.heics"][source] ?? still
            return ImageProbe(
                typeIdentifier: self == .animated ? animatedType : still, frameCount: self == .animated ? 3 : 1,
                pixelSize: PixelSize(width: 640, height: 480), orientation: self == .rotated ? 6 : 1,
                hasAlpha: self == .alpha, hasGainMap: self == .gainMap)
        }
    }

    static let pairs = ImagePlannerTests.imagePairs.filter { $0.source != .svg }
    static let goldens = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Goldens")

    static func plans(_ variant: Variant) throws -> [String: ExecutionPlan] {
        var plans: [String: ExecutionPlan] = [:]
        for pair in pairs {
            let plan = try ImagePlannerTests.plan(pair.source, pair.target, variant.probe(pair.source))
            plans["\(pair.source.rawValue)__\(pair.target.rawValue)"] = plan
        }
        return plans
    }

    @Test func thereAre49Pairs() { #expect(Self.pairs.count == 49) }

    @Test(arguments: Variant.allCases)
    func plansMatchTheirGoldens(variant: Variant) throws {
        let plans = try Self.plans(variant)
        if ProcessInfo.processInfo.environment["ZIVLET_RECORD_GOLDENS"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try FileManager.default.createDirectory(at: Self.goldens, withIntermediateDirectories: true)
            try encoder.encode(plans).write(to: Self.goldens.appending(path: "plans-\(variant.rawValue).json"))
            Issue.record("recorded plans-\(variant.rawValue).json; review it and run again without recording")
            return
        }
        let url = try #require(
            Bundle.module.url(forResource: "plans-\(variant.rawValue)", withExtension: "json", subdirectory: "Goldens"))
        let golden = try JSONDecoder().decode([String: ExecutionPlan].self, from: Data(contentsOf: url))
        #expect(golden.keys.sorted() == plans.keys.sorted())
        for (pair, plan) in plans.sorted(by: { $0.key < $1.key }) {
            #expect(golden[pair] == plan, "\(variant) \(pair)")
        }
    }
}
