import Darwin
import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import ZivletRuntime

@Suite("Save as text (P2-104, plan 18d D10): UTF-8 without BOM, LF, published beside the input")
struct TextFileWriterTests {
    let dir: TempDir

    init() throws { dir = try TempDir(prefix: "zivlet-text-writer") }

    func writer(fallback: URL? = nil) -> TextFileWriter {
        TextFileWriter(fallbackFolder: fallback ?? dir.url.appending(path: "fallback"))
    }

    @Test func theBytesAreTheTextInUTF8WithoutABOM() throws {
        let input = try dir.file("photo.png")
        let url = try writer().write("आज मौसम\nGood day\n", beside: input)
        #expect(url.lastPathComponent == "photo Text.txt")
        let bytes = try Data(contentsOf: url)
        #expect(bytes == Data("आज मौसम\nGood day\n".utf8))
        #expect(!bytes.starts(with: [0xEF, 0xBB, 0xBF]))
    }

    @Test func carriageReturnsAreWrittenAsLineFeeds() throws {
        let url = try writer().write("one\r\ntwo\rthree\n", beside: try dir.file("scan.pdf"))
        #expect(try String(contentsOf: url, encoding: .utf8) == "one\ntwo\nthree\n")
    }

    @Test func aTakenNameGetsACounter() throws {
        let input = try dir.file("photo.png")
        try dir.file("photo Text.txt", "older")
        let url = try writer().write("new", beside: input)
        #expect(url.lastPathComponent == "photo Text 2.txt")
        #expect(try String(contentsOf: dir.url.appending(path: "photo Text.txt"), encoding: .utf8) == "older")
    }

    @Test func aReadOnlyFolderSendsTheFileToTheFallbackFolder() throws {
        let locked = try dir.folder("locked")
        let input = try dir.file("locked/photo.png")
        let fallback = try dir.folder("fallback")
        chmod(locked.path, 0o555)
        defer { chmod(locked.path, 0o755) }
        let url = try writer(fallback: fallback).write("text", beside: input)
        #expect(url.deletingLastPathComponent().standardizedFileURL == fallback.standardizedFileURL)
        #expect(Self.stagingFolders(in: fallback).isEmpty)
    }

    @Test func noStagingFolderIsLeftAfterSuccessOrFailure() throws {
        let input = try dir.file("photo.png")
        _ = try writer().write("text", beside: input)
        #expect(Self.stagingFolders(in: dir.url).isEmpty)
        let locked = try dir.folder("both")
        let lockedInput = try dir.file("both/a.png")
        chmod(locked.path, 0o555)
        defer { chmod(locked.path, 0o755) }
        #expect(throws: JobError.self) { try writer(fallback: locked).write("text", beside: lockedInput) }
        #expect(Self.stagingFolders(in: locked).isEmpty)
    }

    @Test func theInputsQuarantineIsCopied() throws {
        let input = try dir.file("download.png")
        let value = Data("0081;00000000;Zivlet test;".utf8)
        _ = value.withUnsafeBytes { setxattr(input.path, "com.apple.quarantine", $0.baseAddress, $0.count, 0, 0) }
        let url = try writer().write("text", beside: input)
        #expect(Publisher.quarantine(of: url) == value)
    }

    static func stagingFolders(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(Publisher.stagingPrefix) }
    }
}
