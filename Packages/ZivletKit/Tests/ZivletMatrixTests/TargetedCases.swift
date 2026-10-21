import CoreGraphics
import EngineImage
import Foundation
import Testing
import ZivletCore

/// Pairs the one-fixture-per-source matrix cannot check (10g E2): multi-frame sources, multi-page TIFF → PDF, the
/// SVG → PDF page size (D-M4-6) and the Web (sRGB) colour option. Each case first checks that its fixture really
/// has what it tests (more than one frame, a P3 profile), so it cannot pass with nothing to check.
struct TargetedCase: Sendable, CustomTestStringConvertible {
    enum Check: Sendable {
        /// Every source frame is in the output.
        case keepsFrames
        /// One PDF page per source frame, up to the PDF page cap.
        case pagePerFrame
        /// One PDF page of this size in points.
        case page(width: Int, height: Int)
        /// Converted to sRGB from a P3 source.
        case sRGB
    }

    let fixture: String
    /// The name the fixture is dropped as (its extension is what admission reads).
    let droppedAs: String
    let source: FormatID
    let target: FormatID
    let colour: ImageColourOption
    let check: Check

    init(
        _ fixture: String, as droppedAs: String? = nil, _ source: FormatID, to target: FormatID,
        colour: ImageColourOption = .keep, _ check: Check
    ) {
        self.fixture = fixture
        self.droppedAs = droppedAs ?? fixture
        self.source = source
        self.target = target
        self.colour = colour
        self.check = check
    }

    var testDescription: String { "\(fixture) → \(target.rawValue)\(colour == .webSRGB ? " (Web sRGB)" : "")" }

    static let all: [TargetedCase] = [
        TargetedCase("animated.png", .png, to: .webp, .keepsFrames),
        TargetedCase("animated.png", .png, to: .heic, .keepsFrames),
        // ImageIO names a HEIC sequence .heics; Zivlet admits it by content as HEIC.
        TargetedCase("animated.heics", as: "animated.heic", .heic, to: .webp, .keepsFrames),
        TargetedCase("animated.heics", as: "animated.heic", .heic, to: .png, .keepsFrames),
        TargetedCase("pages.tiff", .tiff, to: .pdf, .pagePerFrame),
        // The E1 drawing is 120 × 80 CSS pixels: one point per CSS pixel on the page.
        TargetedCase("drawing.svg", .svg, to: .pdf, .page(width: 120, height: 80)),
        TargetedCase("p3-16bit.png", .png, to: .jpg, colour: .webSRGB, .sRGB),
        TargetedCase("p3-16bit.tiff", .tiff, to: .webp, colour: .webSRGB, .sRGB),
    ]
}

@Suite("Targeted matrix cases (opt-in: ZIVLET_MATRIX)", .enabled(if: MatrixEnvironment.isEnabled))
struct TargetedMatrixTests {
    @Test(arguments: TargetedCase.all)
    func convertsAndKeepsWhatItTests(_ test: TargetedCase) async throws {
        let rig = try await MatrixRig.shared()
        let input = rig.fixtures.appending(path: test.fixture)
        let output = try await rig.convert(input, as: test.droppedAs, to: test.target, colour: test.colour)
        defer { output.discard() }
        switch test.check {
        case .keepsFrames:
            let source = try ImageFacts.read(input)
            try #require(source.frames > 1, "\(test.fixture) has one frame")
            #expect(try ImageFacts.read(output.url).frames == source.frames)
        case .pagePerFrame:
            let source = try ImageFacts.read(input)
            try #require(source.frames > 1, "\(test.fixture) has one page")
            #expect(ImageFacts.pdfPages(output.url) == min(source.frames, ImagePlanner.maxPDFPages))
        case .page(let width, let height):
            #expect(ImageFacts.pdfPages(output.url) == 1)
            #expect(ImageFacts.pdfPageSize(output.url) == CGSize(width: width, height: height))
        case .sRGB:
            try #require(try ImageFacts.read(input).isP3, "\(test.fixture) is not P3")
            let out = try ImageFacts.read(output.url)
            #expect(!out.isP3 && out.colourName?.localizedCaseInsensitiveContains("sRGB") == true, "\(out)")
        }
    }
}
