import Testing
import ZivletCore
import ZivletNotch

@Suite("ZivletNotch module (D-N1)")
@MainActor
struct NotchModuleTests {
    @Test func theShellModuleSeesTheCore() { #expect(Rect2D(x: 1, y: 2, width: 3, height: 4).maxY == 6) }
}
