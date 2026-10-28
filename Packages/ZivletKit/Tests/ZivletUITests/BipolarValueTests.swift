import AppKit
import SwiftUI
import Testing

@testable import ZivletUI

@Suite("The bipolar slider fills from the centre (P2-30, plan 20b A3)")
@MainActor
struct BipolarValueTests {
    @Test(arguments: [(-0.4, -0.4...0), (0, 0...0), (0.7, 0...0.7), (1, 0...1), (-1, -1...0)])
    func theFillRunsFromTheCentreToTheValue(position: Double, fill: ClosedRange<Double>) {
        #expect(BipolarValue.fill(for: position) == fill)
        #expect(BipolarValue(position).fill == fill)
    }

    @Test func positionsOutsideTheTrackAreClamped() {
        #expect(BipolarValue(1.6).position == 1)
        #expect(BipolarValue(-3).position == -1)
        #expect(BipolarValue(.nan).position == 0)
    }

    @Test func arrowKeysStepByAFifthOfATenthAndOptionStepsFiner() {
        let start = BipolarValue(0.5)
        #expect(start.stepped(.up).position.isClose(to: 0.55))
        #expect(start.stepped(.down).position.isClose(to: 0.45))
        #expect(start.stepped(.up, fine: true).position.isClose(to: 0.51))
        #expect(start.stepped(.down, fine: true).position.isClose(to: 0.49))
        #expect(BipolarValue(0.98).stepped(.up).position == 1)
        #expect(start.stepped(.home) == .neutral)
        #expect(start.position == 0.5)
    }

    @Test func theTrackMapsOntoTheToolsOwnRangeAroundItsNeutral() {
        let speed = BipolarRange(lower: 0.25, neutral: 1, upper: 4)
        #expect(speed.value(at: .neutral) == 1)
        #expect(speed.value(at: BipolarValue(-1)) == 0.25)
        #expect(speed.value(at: BipolarValue(1)) == 4)
        #expect(speed.value(at: BipolarValue(0.5)) == 2.5)
        #expect(speed.position(for: 2.5).position.isClose(to: 0.5))
        #expect(speed.position(for: 0.625).position.isClose(to: -0.5))
        #expect(speed.position(for: 99).position == 1)
    }

    @Test func theSliderDrawsAndNamesItsValue() {
        let view = NSHostingView(
            rootView: BipolarSlider(label: "Speed", value: .constant(BipolarValue(-0.4)), valueText: { _ in "0.7×" }))
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.width > 0 && view.fittingSize.height > 0)
        #expect(BipolarSlider.accessibilityValue(BipolarValue(-0.4), valueText: { _ in "0.7×" }) == "0.7×")
    }
}

extension Double {
    func isClose(to other: Double) -> Bool { abs(self - other) < 1e-9 }
}
