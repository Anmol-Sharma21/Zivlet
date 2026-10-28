import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import ZivletUI

#if DEBUG
    @Suite("UI test fixture, tools mode (plan 20b A6, D-M7-12)")
    struct UITestFixtureToolsTests {
        @Test func theModeIsToolsOrConvertAndAnythingElseIsRefused() throws {
            #expect(try UITestFixture.mode(arguments: ["Z", "-UITestMode", "tools"]) == .tools)
            #expect(try UITestFixture.mode(arguments: ["Z", "-UITestMode", "convert"]) == .convert)
            #expect(try UITestFixture.mode(arguments: ["Z", "-UITestFixture", "/tmp/x"]) == nil)
            #expect(throws: UITestFixtureError.unknownMode("wheel")) {
                try UITestFixture.mode(arguments: ["Z", "-UITestMode", "wheel"])
            }
            #expect(throws: UITestFixtureError.missingValue("-UITestMode")) {
                try UITestFixture.mode(arguments: ["Z", "-UITestMode"])
            }
        }

        @Test func theToolIsNamedByItsIdentifier() throws {
            #expect(try UITestFixture.tool(arguments: ["Z", "-UITestTool", "qrScan"]) == .qrScan)
            #expect(try UITestFixture.tool(arguments: ["Z"]) == nil)
            #expect(throws: UITestFixtureError.unknownTool("lockPDF")) {
                try UITestFixture.tool(arguments: ["Z", "-UITestTool", "lockPDF"])
            }
        }

        @Test func theFilesAreTheFoldersVisibleRegularFilesByName() throws {
            let dir = try TempDir()
            for name in ["b.png", "a.pdf", ".hidden"] {
                try Data("x".utf8).write(to: dir.url.appending(path: name))
            }
            try FileManager.default.createDirectory(
                at: dir.url.appending(path: "sub"), withIntermediateDirectories: false)
            let files = try UITestFixture.files(in: dir.url)
            #expect(files.map(\.lastPathComponent) == ["a.pdf", "b.png"])
            #expect(throws: UITestFixtureError.noFiles) {
                try UITestFixture.files(in: dir.url.appending(path: "sub"))
            }
        }
    }
#endif
