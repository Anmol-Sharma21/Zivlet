import Foundation
import Testing
import ZivletCore

@testable import ZivletEngineKit

@Suite("EngineLocator (P1-21): bundled helpers, explicit override, Debug-only dev paths")
struct EngineLocatorTests {
    static let helpers = URL(fileURLWithPath: "/Applications/Zivlet.app/Contents/Helpers")
    static let brew = URL(fileURLWithPath: "/opt/homebrew/bin")

    static func locator(
        executables: Set<String>, environment: [String: String] = [:], development: [URL] = [brew]
    ) -> EngineLocator {
        EngineLocator(
            bundledHelpers: helpers, environment: environment, developmentDirectories: development,
            isExecutable: { executables.contains($0) })
    }

    static var isDebug: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    static func both(in dir: String) -> Set<String> { ["\(dir)/ffmpeg", "\(dir)/ffprobe"] }

    @Test func bundledHelpersWinOverEverythingElse() throws {
        let all = Self.both(in: Self.helpers.path).union(Self.both(in: "/dev/override")).union(
            Self.both(in: "/opt/homebrew/bin"))
        let tools = try Self.locator(executables: all, environment: ["ZIVLET_FFMPEG_DIR": "/dev/override"])
            .locateMediaTools()
        #expect(tools == MediaTools(directory: Self.helpers, origin: .bundled))
        #expect(tools.ffprobe.path == "/Applications/Zivlet.app/Contents/Helpers/ffprobe")
    }

    /// Debug only (index D-M3-19): in Release a launch environment (launchctl setenv, `open --env`) must not make the
    /// signed app run an arbitrary ffmpeg with Zivlet's file-access grants.
    @Test func theOverrideIsHonouredInDebugBuildsOnly() throws {
        let locator = Self.locator(
            executables: Self.both(in: "/dev/override"), environment: ["ZIVLET_FFMPEG_DIR": "/dev/override"],
            development: [])
        #expect(EngineLocator.honoursOverride == Self.isDebug)
        if Self.isDebug {
            #expect(try locator.locateMediaTools().ffmpeg.path == "/dev/override/ffmpeg")
        } else {
            #expect(throws: JobError.engineMissing(.media)) { try locator.locateMediaTools() }
        }
    }

    @Test(.enabled(if: EngineLocator.honoursOverride))
    func theOverrideComesBeforeDevelopmentPaths() throws {
        let all = Self.both(in: "/dev/override").union(Self.both(in: "/opt/homebrew/bin"))
        let tools = try Self.locator(executables: all, environment: ["ZIVLET_FFMPEG_DIR": "/dev/override"])
            .locateMediaTools()
        #expect(tools.origin == .override)
        #expect(tools.ffmpeg.path == "/dev/override/ffmpeg")
    }

    @Test func developmentPathsAreTheLastResort() throws {
        let tools = try Self.locator(executables: Self.both(in: "/opt/homebrew/bin")).locateMediaTools()
        #expect(tools.origin == .development)
    }

    @Test(arguments: [["/opt/homebrew/bin/ffmpeg"], ["/opt/homebrew/bin/ffprobe"], []])
    func aDirectoryNeedsBothTools(present: [String]) {
        #expect(throws: JobError.engineMissing(.media)) {
            try Self.locator(executables: Set(present)).locateMediaTools()
        }
    }

    @Test(arguments: ["relative/bin", "", "/a/../bin"])
    func anUnsafeOverrideIsIgnored(path: String) {
        let executables = Self.both(in: path)
        #expect(throws: JobError.engineMissing(.media)) {
            try Self.locator(executables: executables, environment: ["ZIVLET_FFMPEG_DIR": path], development: [])
                .locateMediaTools()
        }
    }

    @Test func debugBuildsListHomebrewAndReleaseBuildsListNothing() {
        #if DEBUG
            #expect(EngineLocator.defaultDevelopmentDirectories.map(\.path) == ["/opt/homebrew/bin", "/usr/local/bin"])
        #else
            #expect(EngineLocator.defaultDevelopmentDirectories.isEmpty)
        #endif
    }

    @Test func theDefaultInitialiserReadsTheProcessEnvironment() {
        let locator = EngineLocator()
        #expect(locator.bundledHelpers?.lastPathComponent == "Helpers")
    }
}
