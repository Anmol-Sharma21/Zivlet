import Testing
import ZivletShelfCore

@testable import ZivletBox

@Suite("ZivletBox module (D-M5b-1)")
struct BoxModuleTests {
    @Test func theModuleNamesItself() { #expect(Box.moduleName == "ZivletBox") }

    @Test func theModuleSeesTheShelfCore() { #expect(ShelfCore.moduleName == "ZivletShelfCore") }
}
