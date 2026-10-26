import Testing
import ZivletCore

@testable import ZivletShelfCore

@Suite("ZivletShelfCore module (D-M5b-1)")
struct ShelfModuleTests {
    @Test func theModuleSeesTheCore() { #expect(Rect2D(x: 0, y: 0, width: 2, height: 2).maxX == 2) }

    @Test func theModuleNamesItself() { #expect(ShelfCore.moduleName == "ZivletShelfCore") }
}
