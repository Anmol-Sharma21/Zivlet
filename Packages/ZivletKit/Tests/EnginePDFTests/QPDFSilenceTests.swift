import EngineTestSupport
import Foundation
import TestSupport
import Testing

/// Plan 20d C4 (5): the shim prints nothing. Other tests in this process print their own progress, so the calls run
/// in `zivlet-pdf-probe`, a process of their own whose standard output and error are pipes this test reads.
@Suite("qpdf prints nothing (P2-13)")
struct QPDFSilenceTests {
    private final class BundleToken {}

    private static var probe: URL {
        Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent().appending(path: "zivlet-pdf-probe")
    }

    private struct Run {
        let status: Int32
        let output: Data
        let errors: Data
    }

    /// Runs the probe on `input` with three passwords on standard input (never in its arguments).
    private func probe(_ input: URL, into folder: URL, passwords: [String]) throws -> Run {
        let process = Process()
        process.executableURL = Self.probe
        process.arguments = [input.path, folder.path]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        try stdin.fileHandleForWriting.write(contentsOf: Data(passwords.map { $0 + "\n" }.joined().utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus, output: output, errors: errors)
    }

    @Test(arguments: [0, 40, 128])
    func everyCallOfTheSmokeTestIsSilent(keyLength: Int) throws {
        let dir = try TempDir()
        let input =
            keyLength == 0
            ? try PDFFixtures.plain(in: dir.url)
            : try PDFFixtures.encrypted(in: dir.url, keyLength: keyLength, user: "u-pass", owner: "o-pass")
        let folder = try dir.folder("out")

        let run = try probe(input, into: folder, passwords: [keyLength == 0 ? "" : "u-pass", "new user", "new owner"])

        #expect(run.status == 0)
        #expect(run.output.isEmpty)
        #expect(run.errors.isEmpty)
        for name in ["preserved.pdf", "open.pdf", "locked.pdf"] {
            #expect(FileManager.default.fileExists(atPath: folder.appending(path: name).path))
        }
    }

    @Test func aDamagedFileThatQPDFRepairsWarnsWithoutPrinting() throws {
        let dir = try TempDir()
        let input = try PDFFixtures.brokenCrossReference(in: dir.url)

        let run = try probe(input, into: try dir.folder("out"), passwords: ["", "new user", "new owner"])

        #expect(run.status == 0)
        #expect(run.output.isEmpty)
        #expect(run.errors.isEmpty)
    }

    @Test func aWrongPasswordIsSilentToo() throws {
        let dir = try TempDir()
        let input = try PDFFixtures.encrypted(in: dir.url, keyLength: 128, user: "u-pass", owner: "o-pass")

        let run = try probe(input, into: try dir.folder("out"), passwords: ["not it", "new user", "new owner"])

        #expect(run.status == 2)
        #expect(run.output.isEmpty)
        #expect(run.errors.isEmpty)
    }

    @Test func theProbeRefusesWrongArguments() throws {
        let dir = try TempDir()
        let process = Process()
        process.executableURL = Self.probe
        process.arguments = [dir.url.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 64)
    }
}
