import DNGFixture
import Foundation
import ImageIO
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

@Suite("Raw DNG photos: developed by ImageIO, written as ordinary images")
struct ImageDNGTests {
    let run = ImageRun()

    @Test func aDNGTakesThePhotoTargets() {
        #expect(ConversionCatalog.standard.targets(for: .dng) == [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .pdf])
    }

    @Test func theProbeReadsARawSource() throws {
        let dir = try ImageFixture.directory()
        let probe = try ImageReader.probe(try ImageFixture.opaque(.dng, in: dir))
        #expect(probe.typeIdentifier == "com.adobe.raw-image")
        #expect(probe.pixelSize == PixelSize(width: DNGFixture.width, height: DNGFixture.height))
        #expect(probe.frameCount == 1)
    }

    @Test(arguments: [FormatID.jpg, .png, .webp, .heic, .tiff, .avif, .bmp])
    func theDevelopedPictureKeepsItsSizeAndItsTwoHalves(target: FormatID) async throws {
        let dir = try ImageFixture.directory()
        let source = try await offPool { try ImageFixture.opaque(.dng, in: dir) }
        let (_, output) = try await run.convert(source, .dng, to: target, in: dir)
        let image = try ImageFixture.properties(output.url)
        #expect(image[kCGImagePropertyPixelWidth] as? Int == DNGFixture.width)
        #expect(image[kCGImagePropertyPixelHeight] as? Int == DNGFixture.height)
        let left = try ImageFixture.pixel(output.url, x: 40, y: 120)
        let right = try ImageFixture.pixel(output.url, x: 280, y: 120)
        #expect(left[0] > left[2] && right[2] > right[0], "\(target): left \(left), right \(right)")
    }

    @Test func aTIFFMadeFromADNGIsAnOrdinaryTIFF() async throws {
        let dir = try ImageFixture.directory()
        let source = try await offPool { try ImageFixture.opaque(.dng, in: dir) }
        let (_, output) = try await run.convert(source, .dng, to: .tiff, in: dir)
        let opened = try #require(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        #expect(CGImageSourceGetType(opened) as String? == "public.tiff")
        #expect(try ImageFixture.properties(output.url)[kCGImagePropertyDNGDictionary] == nil)
    }

    @Test func aDNGCutShortIsRefusedWithoutAnOutput() async throws {
        let dir = try ImageFixture.directory()
        let url = dir.appending(path: "short.dng")
        try DNGFixture.bytes().prefix(2048).write(to: url)
        await #expect(throws: JobError.self) {
            _ = try await run.convert(url, .dng, to: .jpg, in: dir)
        }
    }
}
