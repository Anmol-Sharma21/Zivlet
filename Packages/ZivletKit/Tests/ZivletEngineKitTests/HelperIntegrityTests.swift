import Foundation
import Testing
import ZivletCore

@testable import ZivletEngineKit

@Suite("Helper code-signature check (A11, 11 §7.4)")
struct HelperIntegrityTests {
    static func adHocSignedCopy(of tool: String, in dir: URL) throws -> URL {
        let url = dir.appending(path: (tool as NSString).lastPathComponent)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: tool), to: url)
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", url.path]
        sign.standardError = FileHandle.nullDevice
        try sign.run()
        sign.waitUntilExit()
        #expect(sign.terminationStatus == 0)
        return url
    }

    static func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "zivlet-integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func aValidAdHocSignatureInsideTheBundlePasses() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = try Self.adHocSignedCopy(of: "/bin/echo", in: dir)
        let policy = HelperIntegrity.Policy(teamID: nil, bundleRoot: dir)
        #expect(throws: Never.self) { try HelperIntegrity.check(tool, policy: policy) }
    }

    @Test func aModifiedBinaryFails() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = try Self.adHocSignedCopy(of: "/bin/echo", in: dir)
        let handle = try FileHandle(forUpdating: tool)
        try handle.seek(toOffset: 0x4000)
        try handle.write(contentsOf: Data([0xFF, 0xFF]))
        try handle.close()
        #expect(throws: JobError.engineDamaged(.media)) {
            try HelperIntegrity.check(tool, policy: .init(teamID: nil, bundleRoot: dir))
        }
    }

    @Test func anUnsignedOrMissingHelperFails() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appending(path: "ffmpeg")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        #expect(throws: JobError.engineDamaged(.media)) {
            try HelperIntegrity.check(script, policy: .init(teamID: nil, bundleRoot: dir))
        }
        #expect(throws: JobError.engineDamaged(.media)) {
            try HelperIntegrity.check(dir.appending(path: "absent"), policy: .init(teamID: nil, bundleRoot: dir))
        }
    }

    @Test func aHelperOutsideTheBundleFails() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = try Self.adHocSignedCopy(of: "/bin/echo", in: dir)
        let elsewhere = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        #expect(throws: JobError.engineDamaged(.media)) {
            try HelperIntegrity.check(tool, policy: .init(teamID: nil, bundleRoot: elsewhere))
        }
    }

    @Test func aSymlinkFromInsideTheBundleToOutsideFails() throws {
        let outside = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: outside) }
        let tool = try Self.adHocSignedCopy(of: "/bin/echo", in: outside)
        let bundle = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: bundle) }
        let link = bundle.appending(path: "ffmpeg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool)
        #expect(throws: JobError.engineDamaged(.media)) {
            try HelperIntegrity.check(link, policy: .init(teamID: nil, bundleRoot: bundle))
        }
    }

    @Test func aTeamRequirementRejectsAnAdHocHelper() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = try Self.adHocSignedCopy(of: "/bin/echo", in: dir)
        #expect(throws: JobError.engineDamaged(.media)) {
            try HelperIntegrity.check(tool, policy: .init(teamID: "ABCDE12345", bundleRoot: dir))
        }
        #expect(throws: JobError.engineDamaged(.media)) {
            try HelperIntegrity.check(tool, policy: .init(teamID: "bad\" or 1", bundleRoot: dir))
        }
    }

    @Test func theRequirementTextNamesTheTeam() {
        #expect(
            HelperIntegrity.Policy(teamID: "ABCDE12345", bundleRoot: URL(fileURLWithPath: "/")).requirement
                == #"anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345""#)
        #expect(HelperIntegrity.Policy(teamID: nil, bundleRoot: URL(fileURLWithPath: "/")).requirement == nil)
        #expect(HelperIntegrity.Policy(teamID: "abc\"; or 1", bundleRoot: URL(fileURLWithPath: "/")).requirement == nil)
    }

    @Test func malformedTeamIDsAreRefused() {
        #expect(HelperIntegrity.Policy.validTeamID("ABCDE12345"))
        #expect(!HelperIntegrity.Policy.validTeamID("abc\"; or 1"))
        #expect(!HelperIntegrity.Policy.validTeamID(""))
        #expect(!HelperIntegrity.Policy.validTeamID("ABCDE123456"))
        #expect(!HelperIntegrity.Policy.validTeamID("abcde12345"))
    }

    /// The test runner is not signed with a Developer ID, so the policy derived from it has no Team ID.
    @Test func theRunningProcessPolicyUsesTheMainBundle() {
        let policy = HelperIntegrity.Policy.current()
        #expect(policy.bundleRoot == Bundle.main.bundleURL)
        #expect(policy.teamID == nil || HelperIntegrity.Policy.validTeamID(policy.teamID ?? ""))
    }

    @Test func onlyBundledHelpersAreChecked() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let elsewhere = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: elsewhere) }
        let checker = SignedHelperCheck(policy: .init(teamID: nil, bundleRoot: elsewhere))
        #expect(throws: Never.self) { try checker.check(MediaTools(directory: dir, origin: .development)) }
        #expect(throws: Never.self) { try checker.check(MediaTools(directory: dir, origin: .override)) }
        #expect(throws: JobError.engineDamaged(.media)) {
            try checker.check(MediaTools(directory: dir, origin: .bundled))
        }
    }

    @Test func signedBundledToolsPass() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let echo = try Self.adHocSignedCopy(of: "/bin/echo", in: dir)
        try FileManager.default.moveItem(at: echo, to: dir.appending(path: "ffmpeg"))
        let cat = try Self.adHocSignedCopy(of: "/bin/cat", in: dir)
        try FileManager.default.moveItem(at: cat, to: dir.appending(path: "ffprobe"))
        let checker = SignedHelperCheck(policy: .init(teamID: nil, bundleRoot: dir))
        #expect(throws: Never.self) { try checker.check(MediaTools(directory: dir, origin: .bundled)) }
    }
}
