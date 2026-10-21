import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

@Suite("Colour: source profile kept by default, Web (sRGB) converts (P1-08, G-6)")
struct ImageColourTests {
    let web = ImageRun(engine: ImageEngine(options: ImageOptions(colour: .webSRGB)))

    static func plan(_ target: FormatID, colour: ImageColourOption) throws -> ImagePipelineSpec {
        let input = try InputItem(url: URL(fileURLWithPath: "/in/a.jpg"), format: .jpg, byteCount: 1)
        let request = try JobRequest(
            input: input, operation: .convert(target), destination: URL(fileURLWithPath: "/in"))
        let probe = ImageProbe(
            typeIdentifier: "public.jpeg", frameCount: 1, pixelSize: ImageFixture.size, orientation: 1, hasAlpha: false)
        let plan = try ImagePlanner.plan(
            request, probe: probe, staged: URL(fileURLWithPath: "/in/.s"), writableTypes: ImageTypes.writable,
            options: ImageOptions(colour: colour))
        return try #require(plan.stages.first?.image)
    }

    @Test func webSRGBConvertsRasterTargets() throws {
        #expect(try Self.plan(.png, colour: .webSRGB).colour == .convertToSRGB)
        #expect(try Self.plan(.webp, colour: .webSRGB).colour == .convertToSRGB)
    }

    @Test func theDefaultKeepsTheProfileAndPDFAlwaysDoes() throws {
        #expect(ImageOptions().colour == .keep)
        #expect(try Self.plan(.png, colour: .keep).colour == .keep)
        #expect(try Self.plan(.pdf, colour: .webSRGB).colour == .keep)
    }

    @Test func aSpecWithoutColourDecodesAsKeep() throws {
        let spec = try Self.plan(.png, colour: .keep)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(spec)) as? [String: Any])
        json["colour"] = nil
        let decoded = try JSONDecoder().decode(
            ImagePipelineSpec.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.colour == .keep)
    }

    @Test(arguments: [FormatID.tiff, .heic, .jpg, .bmp])
    func aWideGamutSourceBecomesEightBitSRGB(target: FormatID) async throws {
        let dir = try ImageFixture.directory()
        let source = try await offPool { try ImageFixture.deepP3PNG(in: dir) }
        let (_, output) = try await web.convert(source, .png, to: target, in: dir)
        let properties = try ImageFixture.properties(output.url)
        #expect((properties[kCGImagePropertyProfileName] as? String)?.contains("P3") != true)
        #expect(properties[kCGImagePropertyDepth] as? Int == 8)
        #expect(try ImageFixture.pixel(output.url, x: 5, y: 10)[0] > 200)
        #expect(try ImageFixture.pixel(output.url, x: 35, y: 10)[2] > 200)
    }

    @Test func webSRGBWebPCarriesNoProfile() async throws {
        let dir = try ImageFixture.directory()
        let source = try await offPool { try ImageFixture.deepP3PNG(in: dir) }
        let (_, output) = try await web.convert(source, .png, to: .webp, in: dir)
        #expect(try ImageFixture.properties(output.url)[kCGImagePropertyProfileName] == nil)
    }

    @Test func transparencyIsKeptOrFlattenedWhileConverting() async throws {
        let dir = try ImageFixture.directory()
        let source = try await offPool { try ImageFixture.alphaPNG(in: dir) }
        let (_, tiff) = try await web.convert(source, .png, to: .tiff, in: dir)
        #expect(try ImageFixture.properties(tiff.url)[kCGImagePropertyHasAlpha] as? Bool == true)
        let (_, jpeg) = try await web.convert(source, .png, to: .jpg, in: dir)
        #expect(try ImageFixture.pixel(jpeg.url, x: 5, y: 10).allSatisfy { $0 > 245 })
    }

    @Test func orientationIsStillAppliedOnce() async throws {
        let dir = try ImageFixture.directory()
        let source = try await offPool { try ImageFixture.rotatedJPEG(in: dir) }
        let (_, output) = try await web.convert(source, .jpg, to: .png, in: dir)
        #expect(try ImageReader.probe(output.url).displaySize == PixelSize(width: 20, height: 40))
    }
}
