import Darwin
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletRuntime

/// First bytes that the content sniffer recognises, for files the factory must admit.
enum Signature {
    static let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    static let heic: [UInt8] = [0, 0, 0, 0x18] + Array("ftypheic".utf8)
    static let mp3: [UInt8] = Array("ID3".utf8) + [3, 0, 0, 0, 0, 0, 0]

    /// The signature for a file name's extension (png, heic or mp3).
    static func bytes(forName name: String) -> [UInt8] {
        switch FormatRegistry.standard.formatID(fileName: name) {
        case .png: png
        case .mp3: mp3
        default: heic
        }
    }

    static func file(_ name: String, _ bytes: [UInt8], in box: Sandbox) throws -> URL {
        let url = box.dir.appending(path: name)
        try Data(bytes + Array(repeating: 0, count: 64)).write(to: url)
        return url
    }
}

@Suite("Admission sniffs content and takes regular files only (G-8, 03a §3.2)")
struct AdmissionSniffingTests {
    @Test func aPNGNamedJPGIsConvertedAsPNGAndSaysSo() throws {
        let box = try Sandbox()
        let url = try Signature.file("holiday.jpg", Signature.png, in: box)
        let request = try #require(JobRequestFactory().requests(for: [url], target: .webp).requests.first)
        #expect(request.input.format == .png && request.input.namedFormat == .jpg)
    }

    @Test func contentMatchingTheNameIsNotFlagged() throws {
        let box = try Sandbox()
        let url = try Signature.file("photo.heic", Signature.heic, in: box)
        let request = try #require(JobRequestFactory().requests(for: [url], target: .jpg).requests.first)
        #expect(request.input.format == .heic && request.input.namedFormat == nil)
    }

    @Test func aPlaylistNamedMP4IsRefusedBeforeAnyEngine() throws {
        let box = try Sandbox()
        let url = try box.file("clip.mp4", "#EXTM3U\n#EXTINF:1,\nfile:///etc/passwd\n")
        let plan = JobRequestFactory().requests(for: [url], target: .mov)
        #expect(plan.requests.isEmpty && plan.rejections.map(\.error) == [.unsupportedInput(.contentMismatch)])
    }

    @Test func aSymlinkIsRefusedEvenWhenItPointsAtAPicture() throws {
        let box = try Sandbox()
        let target = try Signature.file("real.png", Signature.png, in: box)
        let link = box.dir.appending(path: "link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let plan = JobRequestFactory().requests(for: [link], target: .jpg)
        #expect(plan.rejections.map(\.error) == [.unsupportedInput(.notAFile)])
    }

    @Test func aFIFOIsRefusedWithoutBlocking() throws {
        let box = try Sandbox()
        let fifo = box.dir.appending(path: "stream.wav")
        try #require(mkfifo(fifo.path, 0o600) == 0)
        let plan = JobRequestFactory().requests(for: [fifo], target: .mp3)
        #expect(plan.rejections.map(\.error) == [.unsupportedInput(.notAFile)])
    }

    @Test func theCardNotesTheSniffedFormat() async throws {
        let box = try Sandbox()
        let url = try Signature.file("holiday.jpg", Signature.png, in: box)
        let scheduler = JobScheduler(engines: [FakeEngine()], lanes: .standard(performanceCores: 2), records: nil)
        let service = ConversionService(scheduler: scheduler, factory: JobRequestFactory(fallbackFolder: box.dir))
        let batch = await service.convert([url], to: .webp)
        let last = try #require(await service.snapshots(until: batch).last)
        #expect(last.items.first?.notes == [.sniffed(.png)])
        #expect(BatchPresentation.make(last).notes == ["This file is really a PNG; converted as PNG."])
    }

    /// The plan expects transparency to flatten; the engine found none, so the card does not mention it.
    @Test func aNoteTheEngineWithdrawsIsNotShown() async throws {
        let box = try Sandbox()
        let url = try Signature.file("shot.png", Signature.png, in: box)
        let engine = FakeEngine(notes: [.alphaFlattened], withdrawn: [.alphaFlattened])
        let scheduler = JobScheduler(engines: [engine], lanes: .standard(performanceCores: 2), records: nil)
        let service = ConversionService(scheduler: scheduler, factory: JobRequestFactory(fallbackFolder: box.dir))
        let batch = await service.convert([url], to: .jpg)
        let last = try #require(await service.snapshots(until: batch).last)
        #expect(last.items.first?.notes == [] && BatchPresentation.make(last).notes.isEmpty)
    }

    @Test(arguments: [
        (FormatID.png, "a PNG"), (.mp3, "an MP3"), (.avif, "an AVIF"), (.heic, "a HEIC"), (.mkv, "an MKV"),
    ])
    func theNoteUsesTheRightArticle(format: FormatID, phrase: String) {
        let label = FormatRegistry.standard.format(format).wheelLabel
        #expect(BatchPresentation.noteText(.sniffed(format)) == "This file is really \(phrase); converted as \(label).")
    }
}
