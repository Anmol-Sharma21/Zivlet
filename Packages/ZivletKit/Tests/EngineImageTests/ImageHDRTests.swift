import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

/// HDR gain-map sources written by ImageIO from an extended-range image (no committed binaries).
enum HDRFixture {
    static func gainMapImage(_ format: FormatID, in dir: URL) throws -> URL {
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
        let info =
            CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGBitmapInfo.byteOrder16Little.rawValue
        let context = try #require(
            CGContext(
                data: nil, width: ImageFixture.size.width, height: ImageFixture.size.height, bitsPerComponent: 16,
                bytesPerRow: 0, space: space, bitmapInfo: info))
        context.setFillColor(try #require(CGColor(colorSpace: space, components: [4, 4, 4, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        context.setFillColor(try #require(CGColor(colorSpace: space, components: [0, 0, 0.8, 1])))
        context.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        let url = dir.appending(path: "hdr.\(format.rawValue)")
        let type = FormatRegistry.standard.format(format).contentTypes[0] as CFString
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil))
        let request = [kCGImageDestinationEncodeRequest: kCGImageDestinationEncodeToISOGainmap]
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), request as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    static func hasGainMap(_ url: URL) throws -> Bool {
        let source = try AnimationFixture.source(url)
        return CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
    }
}

@Suite("HDR gain maps tone-mapped for SDR targets (P1-08, G-6)")
struct ImageHDRTests {
    let run = ImageRun()

    @Test(arguments: [FormatID.heic, .avif])
    func gainMapsAreFoundByTheProbe(format: FormatID) async throws {
        let dir = try ImageFixture.directory()
        let url = try await offPool { try HDRFixture.gainMapImage(format, in: dir) }
        #expect(try ImageReader.probe(url).hasGainMap)
        #expect(try !ImageReader.probe(try await offPool { try ImageFixture.opaque(format, in: dir) }).hasGainMap)
    }

    @Test(arguments: [(FormatID.heic, FormatID.png), (.heic, .jpg), (.avif, .webp), (.heic, .tiff), (.avif, .pdf)])
    func aGainMapSourceIsSavedInStandardRangeAndSaysSo(source: FormatID, target: FormatID) async throws {
        let dir = try ImageFixture.directory()
        let url = try await offPool { try HDRFixture.gainMapImage(source, in: dir) }
        let (plan, output) = try await run.convert(url, source, to: target, in: dir)
        #expect(plan.notes == [.hdrToneMapped])
        #expect(plan.stages[0].image?.decodeToSDR == true)
        guard target != .pdf else { return }
        #expect(try !HDRFixture.hasGainMap(output.url))
        #expect(try ImageFixture.properties(output.url)[kCGImagePropertyDepth] as? Int == 8)
        #expect(try ImageFixture.pixel(output.url, x: 5, y: 10).allSatisfy { $0 > 200 })
    }

    @Test func standardRangeSourcesAreUntouched() throws {
        let plan = try ImagePlannerTests.plan(.heic, .png)
        #expect(plan.notes.isEmpty && plan.stages[0].image?.decodeToSDR == false)
    }
}
