import Foundation
import Testing

@testable import ZivletEngineKit

/// Helpers that parse untrusted media run under a deny-by-default profile (the M4 review): they read their own
/// files, the job's input and the system; they write only into the job's private folder; no network.
@Suite("Helper sandbox")
struct HelperSandboxTests {
    let runner = SubprocessRunner()

    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "zivlet-sandbox-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theProfileDeniesByDefaultAndNamesOnlyTheJobsFiles() {
        let sandbox = HelperSandbox(
            reads: [URL(filePath: "/Users/someone/Movies/in.mov")], writes: [URL(filePath: "/private/var/stage")])
        let profile = sandbox.profile(helper: URL(filePath: "/Applications/Zivlet.app/Contents/Helpers/ffmpeg"))
        #expect(profile.hasPrefix("(version 1)\n(deny default)"))
        #expect(profile.contains(#"(allow process-exec (literal "/Applications/Zivlet.app/Contents/Helpers/ffmpeg"))"#))
        #expect(profile.contains(#"(allow file-read* (subpath "/Applications/Zivlet.app/Contents"))"#))
        #expect(profile.contains(#"(allow file-read* (literal "/Users/someone/Movies/in.mov"))"#))
        #expect(profile.contains(#"(allow file-read* file-write* (subpath "/private/var/stage"))"#))
        #expect(profile.hasSuffix("(deny network*)\n"))
    }

    @Test func quotesAndBackslashesInPathsAreEscaped() {
        let profile = HelperSandbox(reads: [URL(filePath: #"/tmp/a "b"\c.mov"#)]).profile(
            helper: URL(filePath: "/bin/cat"))
        #expect(
            profile.contains(#"(literal "/tmp/a \"b\"\\c.mov")"#) || profile.contains(#"/private/tmp/a \"b\"\\c.mov"#))
    }

    @Test func theLauncherRunsTheHelperUnderTheProfile() {
        let sandbox = HelperSandbox(reads: [])
        let request = SubprocessRequest(executable: URL(filePath: "/bin/echo"), arguments: ["hi"], sandbox: sandbox)
        let launch = request.launch
        #expect(launch.executable == HelperSandbox.launcher)
        #expect(launch.arguments == ["-p", sandbox.profile(helper: URL(filePath: "/bin/echo")), "/bin/echo", "hi"])
        let plain = SubprocessRequest(executable: URL(filePath: "/bin/echo"), arguments: ["hi"])
        #expect(plain.launch.executable.path == "/bin/echo" && plain.launch.arguments == ["hi"])
    }

    @Test func aSandboxedHelperReadsItsInputButNothingElse() async throws {
        let dir = try Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (allowed, other) = (dir.appending(path: "in.txt"), dir.appending(path: "other.txt"))
        try Data("input".utf8).write(to: allowed)
        try Data("secret".utf8).write(to: other)
        let sandbox = HelperSandbox(reads: [allowed])
        let ok = try await runner.run(
            SubprocessRequest(executable: URL(filePath: "/bin/cat"), arguments: [allowed.path], sandbox: sandbox))
        #expect(ok.termination == .exited(0) && String(decoding: ok.stdout, as: UTF8.self) == "input")
        let refused = try await runner.run(
            SubprocessRequest(executable: URL(filePath: "/bin/cat"), arguments: [other.path], sandbox: sandbox))
        #expect(refused.termination != .exited(0) && refused.stdout.isEmpty)
    }

    @Test func aSandboxedHelperWritesOnlyIntoItsFolder() async throws {
        let dir = try Self.folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let stage = dir.appending(path: "stage", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let source = dir.appending(path: "in.txt")
        try Data("input".utf8).write(to: source)
        let sandbox = HelperSandbox(reads: [source], writes: [stage])
        let copy = { (to: URL) in
            SubprocessRequest(
                executable: URL(filePath: "/bin/cp"), arguments: [source.path, to.path], sandbox: sandbox)
        }
        #expect(try await runner.run(copy(stage.appending(path: "out.txt"))).termination == .exited(0))
        #expect(try await runner.run(copy(dir.appending(path: "escape.txt"))).termination != .exited(0))
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "escape.txt").path))
    }
}
