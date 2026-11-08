import CoreGraphics
import DNGFixture
import EngineVision
import Foundation
import Synchronization
import TestSupport
import Testing

/// READ QR and COPY TEXT share this decode, so a raw photo reaches both.
@Suite("A raw DNG reaches text recognition developed, at full size")
struct ImageTextSourceDNGTests {
    let folder: TempDir

    init() throws { folder = try TempDir() }

    @Test func aDNGIsDevelopedForRecognition() async throws {
        let url = folder.url.appending(path: "photo.dng")
        try DNGFixture.bytes().write(to: url)
        let recognizer = RecordingRecognizer()
        _ = try await ImageTextSource.read(url, recognizer: recognizer, languages: [])
        #expect(recognizer.sizes.withLock { $0 } == [CGSize(width: DNGFixture.width, height: DNGFixture.height)])
    }
}
