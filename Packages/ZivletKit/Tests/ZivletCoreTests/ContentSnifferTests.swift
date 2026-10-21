import Foundation
import Testing

@testable import ZivletCore

@Suite("Content sniffing (G-8, 03a §3.2)")
struct ContentSnifferTests {
    static func padded(_ bytes: [UInt8]) -> Data { Data(bytes + Array(repeating: 0, count: 32)) }

    @Test(
        arguments: [
            ([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], FormatID.png),
            ([0xFF, 0xD8, 0xFF, 0xE0], .jpg),
            (Array("RIFF\0\0\0\0WEBPVP8 ".utf8), .webp),
            (Array("RIFF\0\0\0\0WAVEfmt ".utf8), .wav),
            ([0, 0, 0, 0x18] + Array("ftypheic".utf8), .heic),
            ([0, 0, 0, 0x1C] + Array("ftypavif".utf8), .avif),
            (Array("fLaC".utf8), .flac),
            (Array("OggS".utf8), .ogg),
            ([0x1A, 0x45, 0xDF, 0xA3], .mkv),
        ] as [([UInt8], FormatID)])
    func knownMagicBytes(bytes: [UInt8], format: FormatID) {
        #expect(ContentSniffer.sniff(Self.padded(bytes)) == format)
    }

    @Test(
        arguments: [
            (Array("GIF89a".utf8), FormatID.gif), (Array("BM".utf8), .bmp), (Array("II*\0".utf8), .tiff),
            (Array("MM\0*".utf8), .tiff), (Array("RIFF\0\0\0\0AVI LIST".utf8), .avi),
            (Array("FORM\0\0\0\0AIFFCOMM".utf8), .aiff), (Array("ID3\u{3}\0\0\0\0\0\0".utf8), .mp3),
            ([0xFF, 0xFB, 0x90, 0x64], .mp3), ([0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11], .wmv),
            ([0, 0, 0, 0x20] + Array("ftypisom".utf8), .mp4), ([0, 0, 0, 0x14] + Array("ftypqt  ".utf8), .mov),
            ([0, 0, 0, 0x20] + Array("ftypM4A ".utf8), .m4a), ([0, 0, 0, 0x08] + Array("wide".utf8), .mov),
            ([0, 0, 0, 0x1C] + Array("ftypmif1\0\0\0\0avif".utf8), .avif),
        ] as [([UInt8], FormatID)])
    func moreContainers(bytes: [UInt8], format: FormatID) {
        #expect(ContentSniffer.sniff(Self.padded(bytes)) == format)
    }

    @Test func webMIsToldApartFromMatroskaByItsDocType() {
        let webm: [UInt8] = [0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x82, 0x84] + Array("webm".utf8)
        #expect(ContentSniffer.sniff(Self.padded(webm)) == .webm)
    }

    @Test func svgTextIsFoundAfterADeclarationAndAComment() {
        let text =
            "\u{FEFF}<?xml version=\"1.0\"?>\n<!-- drawn by hand -->\n<svg xmlns=\"http://www.w3.org/2000/svg\"/>"
        #expect(ContentSniffer.sniff(Data(text.utf8)) == .svg)
        #expect(ContentSniffer.sniff(Data("<?xml version=\"1.0\"?><note/>".utf8)) == nil)
    }

    @Test(arguments: ["#EXTM3U\n#EXT-X-VERSION:3\n", "ffconcat version 1.0\nfile 'a.mp4'\n", "PK\u{3}\u{4}"])
    func playlistsAndArchivesAreNamedSoTheyCanBeRefused(text: String) {
        #expect(ContentSniffer.classify(Data(text.utf8)) == .refusable)
    }

    @Test(arguments: ["%PDF-1.7\n", "  \n#EXTM3U\n", "<?xml version=\"1.0\"?><MPD xmlns=\"urn:mpeg:dash\">"])
    func documentsAndStreamingManifestsAreRefusable(text: String) {
        #expect(ContentSniffer.classify(Data(text.utf8)) == .refusable)
    }

    @Test func oggOpusIsToldApartFromOggVorbis() {
        let opus = Data(Array("OggS".utf8) + Array(repeating: 0, count: 24) + Array("OpusHead".utf8))
        #expect(ContentSniffer.sniff(opus) == .opus)
    }

    @Test(arguments: ["testsrc2=d=1:s=64x48", "", "plain words", "\u{0}\u{0}\u{0}\u{0}"])
    func unknownContentIsUnknown(text: String) {
        #expect(ContentSniffer.classify(Data(text.utf8)) == .unknown)
    }

    @Test func gzipIsNamedAsGzip() {
        #expect(ContentSniffer.sniff(Self.padded([0x1F, 0x8B, 0x08, 0x00])) == .gz)
    }
}

@Suite("Admission by content (G-8): the sniffed type wins")
struct ContentAdmissionTests {
    static let png = ContentSnifferTests.padded([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test func matchingContentKeepsTheNamedFormat() throws {
        let verdict = try ContentAdmission.resolve(named: .png, header: Self.png, target: .jpg)
        #expect(verdict == ContentAdmission.Verdict(format: .png, isSniffed: false))
    }

    @Test func aPNGNamedJPEGIsConvertedAsPNG() throws {
        let verdict = try ContentAdmission.resolve(named: .jpg, header: Self.png, target: .webp)
        #expect(verdict == ContentAdmission.Verdict(format: .png, isSniffed: true))
    }

    @Test func aSniffedPairOutsideTheCatalogIsAMismatch() {
        #expect(throws: JobError.unsupportedInput(.contentMismatch)) {
            try ContentAdmission.resolve(named: .jpg, header: Self.png, target: .png)
        }
    }

    @Test(arguments: ["#EXTM3U\n", "testsrc2=d=1", "PK\u{3}\u{4}rest"])
    func refusableOrUnknownContentIsAMismatch(text: String) {
        #expect(throws: JobError.unsupportedInput(.contentMismatch)) {
            try ContentAdmission.resolve(named: .mp4, header: Data(text.utf8), target: .mov)
        }
    }

    @Test(
        arguments: [
            (FormatID.mov, [0, 0, 0, 0x20] + Array("ftypisom".utf8)), (.m4a, [0, 0, 0, 0x20] + Array("ftypisom".utf8)),
            (.webm, [0x1A, 0x45, 0xDF, 0xA3]),
            (.ogg, Array("OggS".utf8) + Array(repeating: 0, count: 24) + Array("OpusHead".utf8)),
            (.wma, [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11]), (.svg, [0x1F, 0x8B, 0x08, 0x00]),
            (.avif, [0, 0, 0, 0x18] + Array("ftypheic".utf8)),
            (.flac, Array("ID3\u{4}\0\0\u{7F}\u{7F}\u{7F}\u{7F}".utf8)),
        ] as [(FormatID, [UInt8])])
    func oneContainerFamilyKeepsTheNamedFormat(named: FormatID, bytes: [UInt8]) throws {
        let target = try #require(ConversionCatalog.standard.targets(for: named).first)
        let verdict = try ContentAdmission.resolve(
            named: named, header: ContentSnifferTests.padded(bytes), target: target)
        #expect(verdict == ContentAdmission.Verdict(format: named, isSniffed: false))
    }

    @Test func formatsWithoutASignatureTableAreNotSniffed() throws {
        let verdict = try ContentAdmission.resolve(named: .txt, header: Data("anything".utf8), target: .pdf)
        #expect(verdict == ContentAdmission.Verdict(format: .txt, isSniffed: false))
    }
}
