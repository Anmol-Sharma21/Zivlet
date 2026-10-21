import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

/// zivlet-svg bounds the work of untrusted SVGs (the M4 review): costly filters lower the output size, documents
/// still too costly are refused, embedded raster images are capped by their headers and charged to the decode budget.
@Suite("SVG limits: filter work and embedded images")
struct SVGLimitTests {
    let run = ImageRun()

    static func filtered(_ primitives: String) -> String {
        #"<svg xmlns="http://www.w3.org/2000/svg" width="4096" height="4096"><filter id="f">"# + primitives
            + ##"</filter><rect width="4096" height="4096" fill="#08f" filter="url(#f)"/></svg>"##
    }

    /// A PNG header claiming `width` × `height`; the header is all that is checked before rendering.
    static func embedded(width: UInt32, height: UInt32, count: Int = 1) -> String {
        var header: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
        for value in [width, height] { header += withUnsafeBytes(of: value.bigEndian, Array.init) }
        header += [8, 6, 0, 0, 0, 0, 0, 0, 0]
        let image =
            #"<image href="data:image/png;base64,\#(Data(header).base64EncodedString())" width="10" height="10"/>"#
        return #"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">"#
            + String(repeating: image, count: count) + "</svg>"
    }

    @Test func aCostlyFilterIsDrawnSmallerAndThePlanKnowsTheSize() async throws {
        let dir = try ImageFixture.directory()
        let svg = Self.filtered(String(repeating: #"<feGaussianBlur stdDeviation="5"/>"#, count: 20))
        let source = try SVGFixture.write(svg, named: "blurs.svg", in: dir)
        let probe = try SVGRenderer.probe(source)
        #expect(probe.pixelSize.width < SVGGeometry.maxEdge && probe.pixelSize.width >= 256)
        #expect(probe.pixelSize.width == probe.pixelSize.height)
        let (plan, output) = try await run.convert(source, .svg, to: .png, in: dir)
        #expect(plan.stages.first?.image?.svg?.maxEdge == probe.pixelSize.width)
        #expect(try ImageReader.probe(output.url).pixelSize == probe.pixelSize)
    }

    @Test(arguments: [
        filtered(#"<feMorphology radius="2000"/>"#),
        embedded(width: 10_000, height: 10_000),
        embedded(width: 2_000, height: 2_000, count: 65),
    ])
    func whatCostsTooMuchIsRefusedBeforeRendering(svg: String) throws {
        let dir = try ImageFixture.directory()
        let source = try SVGFixture.write(svg, named: "costly.svg", in: dir)
        #expect(throws: JobError.unsupportedInput(.tooLarge)) { try SVGRenderer.probe(source) }
    }

    /// resvg decodes embedded images itself, so the largest one is reserved from the decode budget too.
    @Test func embeddedImagesAreChargedToTheDecodeBudget() async throws {
        let dir = try ImageFixture.directory()
        let source = try SVGFixture.write(Self.embedded(width: 2_000, height: 2_000), named: "img.svg", in: dir)
        let probe = try SVGRenderer.probe(source)
        #expect(probe.svg?.embeddedPixels == 4_000_000)
        let input = try InputItem(url: source, format: .svg, byteCount: 1)
        let request = try JobRequest(input: input, operation: .convert(.png), destination: dir)
        let plan = try await run.engine.prepare(
            request, workspace: JobWorkspace(job: request.id, stagedFile: dir.appending(path: ".zivlet-x")))
        #expect(plan.stages.first?.image?.svg?.reservedPixels == 4_000_000)
        #expect(ImageEngine.reservation(plan) == 80 * 80 + 4_000_000)
    }
}
