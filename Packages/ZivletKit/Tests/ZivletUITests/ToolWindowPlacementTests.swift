import CoreGraphics
import Testing

@testable import ZivletUI

@Suite("The tool window opens at the wheel's place, inside the screen (P2-30, plan 20b A2)")
struct ToolWindowPlacementTests {
    static let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    static let size = CGSize(width: 340, height: 200)
    static let margin = ToolWindowPlacement.margin

    static func frame(_ center: CGPoint, size: CGSize = size, screen: CGRect = screen) -> CGRect {
        ToolWindowPlacement.frame(size: size, wheelCenter: center, visibleFrame: screen)
    }

    @Test func itIsCentredOnTheWheel() {
        #expect(Self.frame(CGPoint(x: 700, y: 400)) == CGRect(x: 530, y: 300, width: 340, height: 200))
    }

    @Test func itStaysInsideEachEdgeByTheMargin() {
        #expect(Self.frame(CGPoint(x: 10, y: 400)).minX == Self.margin)
        #expect(Self.frame(CGPoint(x: 1430, y: 400)).maxX == 1440 - Self.margin)
        #expect(Self.frame(CGPoint(x: 700, y: 5)).minY == Self.margin)
        #expect(Self.frame(CGPoint(x: 700, y: 870)).maxY == 875 - Self.margin)
    }

    @Test func aCornerClampsBothAxes() {
        let frame = Self.frame(CGPoint(x: 1439, y: 874))
        #expect(frame.maxX == 1440 - Self.margin && frame.maxY == 875 - Self.margin)
        #expect(frame.size == Self.size)
    }

    @Test func aSecondScreenIsMeasuredInItsOwnCoordinates() {
        let right = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        let frame = Self.frame(CGPoint(x: 1450, y: -190), screen: right)
        #expect(frame.minX == 1440 + Self.margin && frame.minY == -200 + Self.margin)
    }

    /// The window keeps its top as its content grows, and moves up only as far as the bottom margin needs.
    @Test func growingKeepsTheTopUntilTheBottomMarginIsReached() {
        let placed = CGRect(x: 100, y: 400, width: 340, height: 200)
        let grown = { (height: CGFloat, frame: CGRect) in
            ToolWindowPlacement.grown(frame, toHeight: height, visibleFrame: Self.screen)
        }
        #expect(grown(300, placed) == CGRect(x: 100, y: 300, width: 340, height: 300))
        let low = CGRect(x: 100, y: Self.margin, width: 340, height: 215)
        #expect(grown(285, low) == CGRect(x: 100, y: Self.margin, width: 340, height: 285))
        let tooTall = grown(2_000, low)
        #expect(tooTall.maxY == 875 - Self.margin && tooTall.height == 2_000)
        #expect(grown(150, placed) == CGRect(x: 100, y: 450, width: 340, height: 150))
    }

    @Test func aScreenSmallerThanTheWindowKeepsItsTopLeftVisible() {
        let small = CGRect(x: 0, y: 0, width: 300, height: 150)
        let frame = Self.frame(CGPoint(x: 150, y: 75), screen: small)
        #expect(frame.minX == Self.margin)
        #expect(frame.maxY == 150 - Self.margin)
        #expect(frame.size == Self.size)
    }
}
