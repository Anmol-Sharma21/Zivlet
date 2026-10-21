import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineMedia

@Suite("Media planner robustness against hostile probes and requests")
struct MediaRobustnessTests {
    func argv(_ r: MediaPlanRequest) throws -> [String] { try MediaPlanner.plan(r).passes[0].argv }

    static let unusableFrameRates: [Double] = [0, -5, .nan, .infinity, -.infinity, 1e300]

    @Test(arguments: unusableFrameRates)
    func gifOutputIgnoresAnUnusableSourceFrameRate(fps: Double) throws {
        let args = try argv(Fx.request(.mp4, .gif, Fx.info(Fx.video(0, "h264", fps: fps))))
        let graph = try #require(args.firstIndex(of: "-filter_complex").map { args[$0 + 1] })
        #expect(graph.hasPrefix("[0:0]fps=15,"))
    }

    @Test(arguments: unusableFrameRates)
    func gifToLegacyVideoOmitsTheRateForAnUnusableSourceFrameRate(fps: Double) throws {
        let gif = Fx.video(0, "gif", 300, 200, fps: fps, pixFmt: "bgra")
        #expect(try !argv(Fx.request(.gif, .avi, Fx.info(gif))).contains("-r"))
    }

    /// Every non-media catalog pair (image, document, data, archive) is refused before any planner runs.
    @Test func nonMediaCatalogPairsAreRefused() {
        let media: Set<FormatCategory> = [.audio, .video, .gif]
        let registry = FormatRegistry.standard
        let pairs = ConversionCatalog.standard.pairs.filter {
            !media.contains(registry.format($0.source).category) || !media.contains(registry.format($0.target).category)
        }
        #expect(pairs.count == ConversionCatalog.standard.pairs.count - 104)
        for pair in pairs {
            #expect(throws: MediaPlanError.pairNotSupported(pair.source, pair.target)) {
                try MediaPlanner.plan(Fx.request(pair.source, pair.target, Fx.info()))
            }
        }
    }

    @Test func theCatalogCanBeInjected() throws {
        let catalog = try ConversionCatalog(rows: [ConversionRow(.mp4, [.mkv])], registry: .standard)
        let info = Fx.info(Fx.video(0, "h264"))
        #expect(throws: MediaPlanError.pairNotSupported(.mp4, .mov)) {
            try MediaPlanner.plan(Fx.request(.mp4, .mov, info), catalog: catalog)
        }
        #expect(try MediaPlanner.plan(Fx.request(.mp4, .mkv, info), catalog: catalog).lane == .remux)
    }

    static func request(source: String, staged: String) -> MediaPlanRequest {
        MediaPlanRequest(
            source: source, sourceFormat: .mp4, info: Fx.info(Fx.video(0, "h264")), target: .mov, staged: staged)
    }

    @Test(arguments: [
        "/in/../etc/x.mp4", "/in/..", "/in/x\t.mp4", "/in/x\r.mp4", "/in/\u{1B}x.mp4", "/in/x\u{7F}.mp4",
        "/in/x\u{85}.mp4",
    ])
    func unsafePathsAreRefused(path: String) {
        #expect(throws: MediaPlanError.invalidPath(path)) {
            try MediaPlanner.plan(Self.request(source: path, staged: "/out/y.mov"))
        }
        #expect(throws: MediaPlanError.invalidPath(path)) {
            try MediaPlanner.plan(Self.request(source: "/in/x.mp4", staged: path))
        }
    }

    @Test(arguments: ["/in/x.mp4", "/in/./x.mp4", "//in//x.mp4", "/in/x.mp4/"])
    func stagedMustNotBeTheSource(staged: String) {
        #expect(throws: MediaPlanError.invalidPath(staged)) {
            try MediaPlanner.plan(Self.request(source: "/in/x.mp4", staged: staged))
        }
    }

    @Test func dotsInsideNamesAreFine() throws {
        let plan = try MediaPlanner.plan(Self.request(source: "/in/a..b.mp4", staged: "/out/.y.mov"))
        #expect(plan.passes[0].argv.last == "file:/out/.y.mov")
    }

    @Test func plausibleFrameRatesStillApply() throws {
        let gif = Fx.video(0, "gif", 300, 200, fps: 120, pixFmt: "bgra")
        #expect(try argv(Fx.request(.gif, .wmv, Fx.info(gif))).contains(subsequence: ["-r", "50"]))
        #expect(Fx.video(0, "h264", fps: 29.97).usableFrameRate == 29.97)
        #expect(Fx.video(0, "h264", fps: .nan).usableFrameRate == nil)
    }
}

@Suite("FFmpeg plan model invariants")
struct FFmpegPlanModelTests {
    @Test(arguments: [0, -1, Double.nan, .infinity])
    func passesRefuseNonPositiveOrNonFiniteWeights(weight: Double) {
        #expect(throws: MediaPlanError.invalidPass) { try FFmpegPass(argv: ["-i", "x"], weight: weight) }
    }

    @Test func passesRefuseAnEmptyArgvAndPlansRefuseNoPasses() throws {
        #expect(throws: MediaPlanError.invalidPass) { try FFmpegPass(argv: [], weight: 1) }
        #expect(throws: MediaPlanError.invalidPass) {
            try FFmpegPlan(passes: [], expectedDurationMicros: nil, lane: .remux)
        }
        let plan = try FFmpegPlan(
            passes: [FFmpegPass(argv: ["a"], weight: 2), FFmpegPass(argv: ["b"], weight: 1)],
            expectedDurationMicros: 5, lane: .swVideo)
        #expect(plan.passes.map(\.weight) == [2, 1])
    }

    @Test func decodingRunsTheSameChecks() throws {
        let valid = #"{"passes":[{"argv":["a"],"weight":1}],"lane":"remux"}"#
        #expect(try JSONDecoder().decode(FFmpegPlan.self, from: Data(valid.utf8)).passes.count == 1)
        for json in [
            #"{"passes":[{"argv":["a"],"weight":0}],"lane":"remux"}"#,
            #"{"passes":[],"lane":"remux"}"#,
        ] {
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(FFmpegPlan.self, from: Data(json.utf8)) }
        }
    }

    @Test(arguments: [
        (MediaOptions(heightLimit: 480), MediaPlanError.invalidOption(.heightLimit, 480)),
        (MediaOptions(gifWidthLimit: 100), .invalidOption(.gifWidthLimit, 100)),
    ])
    func invalidOptionsCarryATypedOption(options: MediaOptions, error: MediaPlanError) {
        #expect(throws: error) {
            try MediaPlanner.plan(Fx.request(.mp4, .gif, Fx.info(Fx.video(0, "h264")), options: options))
        }
    }
}
