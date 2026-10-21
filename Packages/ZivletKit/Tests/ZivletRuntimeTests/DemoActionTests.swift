import Foundation
import Testing
import ZivletCore

@testable import ZivletRuntime

@Suite("DEBUG action demo arguments (C7)")
struct DemoActionTests {
    @Test func demoActionArgumentsParse() throws {
        let parsed = try DemoAction.parse(arguments: ["Zivlet", "-ZivletDemoAction", "/tmp/a.txt", "copyFilePath"])
        #expect(parsed == DemoAction(url: URL(fileURLWithPath: "/tmp/a.txt"), action: .copyFilePath, optionHeld: false))
        let quoted = try DemoAction.parse(
            arguments: ["-ZivletDemoAction", "/tmp/a b", "copyFilePath", "-ZivletDemoOption", "YES"])
        #expect(quoted?.optionHeld == true)
        #expect(try DemoAction.parse(arguments: ["Zivlet"]) == nil)
    }

    @Test(arguments: [
        (["-ZivletDemoAction", "/tmp/a.txt"], DemoActionError.missingValue("-ZivletDemoAction")),
        (["-ZivletDemoAction", "a.txt", "copyTo"], .notAbsolute("a.txt")),
        (["-ZivletDemoAction", "/a.txt", "launch"], .unknownAction("launch")),
        (["-ZivletDemoAction", "/a.txt", "moveTo"], .needsAPerson("moveTo")),
        (["-ZivletDemoAction", "/a.txt", "shareAirDrop"], .needsAPerson("shareAirDrop")),
    ])
    func badDemoActionArgumentsAreTyped(arguments: [String], error: DemoActionError) {
        #expect(throws: error) { try DemoAction.parse(arguments: arguments) }
    }
}

extension DemoActionTests {
    @Test func theOptionFlagNeedsYes() throws {
        let base = ["-ZivletDemoAction", "/tmp/a", "copyFilePath"]
        #expect(try DemoAction.parse(arguments: base + ["-ZivletDemoOption", "NO"])?.optionHeld == false)
        #expect(try DemoAction.parse(arguments: base + ["-ZivletDemoOption"])?.optionHeld == false)
    }
}
