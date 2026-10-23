import SwiftUI
import Testing

@testable import ZivletNotch

@Suite("Island shape (D-N10)")
struct IslandShapeTests {
    @Test func theIncreaseContrastOutlineIsDrawnInsideTheShapeSoTheClipKeepsAllOfIt() {
        let rect = CGRect(x: 0, y: 0, width: 232, height: 62)
        let outline = IslandShape(top: 0, bottom: 12).inset(by: 0.5).path(in: rect).boundingRect
        #expect(outline == rect.insetBy(dx: 0.5, dy: 0.5))
    }

    @Test func insetCornersShrinkWithTheInsetSoTheyStayConcentric() {
        let shape = IslandShape(top: 0, bottom: 12).inset(by: 2)
        #expect(shape.top == 0 && shape.bottom == 10)
    }
}
