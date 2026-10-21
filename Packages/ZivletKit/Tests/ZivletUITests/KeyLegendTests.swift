import CoreGraphics
import Testing
import ZivletSettings
import ZivletTrigger

@testable import ZivletUI

@Suite("Key legend for the first three drags (P1-47 coach)")
struct KeyLegendTests {
    static func onboarding(completed: Bool, left: Int) -> OnboardingGroup {
        var group = OnboardingGroup()
        group.completed = completed
        group.practiceDragsLeft = left
        return group
    }

    @Test func theLegendNamesEachWheelsKey() throws {
        #expect(KeyLegend.text(.standard) == "⇧ Convert · ⌘ Tools · ⌃ Actions")
        let custom = try TriggerBindings(convert: .option, tools: .shift, actions: .control)
        #expect(KeyLegend.text(custom) == "⌥ Convert · ⇧ Tools · ⌃ Actions")
    }

    @Test func itShowsOnlyAfterOnboardingWhileDragsAreLeft() {
        #expect(!KeyLegend.shows(Self.onboarding(completed: false, left: 3)))
        #expect(KeyLegend.shows(Self.onboarding(completed: true, left: 3)))
        #expect(!KeyLegend.shows(Self.onboarding(completed: true, left: 0)))
    }

    @Test func eachShownDragCountsDownToZero() {
        var group = Self.onboarding(completed: true, left: 3)
        for _ in 0..<5 { group = KeyLegend.counting(group) }
        #expect(group.practiceDragsLeft == 0)
    }

    @Test func theLegendSitsBesideTheWheelInsideTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 260, height: 32)
        let right = KeyLegend.frame(size: size, beside: CGRect(x: 400, y: 300, width: 300, height: 300), screen: screen)
        #expect(right.minX == 712 && right.midY == 450)
        let left = KeyLegend.frame(size: size, beside: CGRect(x: 1100, y: 300, width: 300, height: 300), screen: screen)
        #expect(left.maxX == 1088)
        let low = KeyLegend.frame(size: size, beside: CGRect(x: 400, y: -200, width: 300, height: 300), screen: screen)
        #expect(low.minY >= 12)
    }
}

@Suite("Key legend panel (P1-47 coach)")
@MainActor
struct KeyLegendPanelTests {
    @Test func showsBesideTheWheelAndHides() {
        let panel = KeyLegendPanel()
        panel.show(KeyLegend.text(.standard), beside: CGRect(x: -5000, y: -5000, width: 300, height: 300))
        #expect(panel.isVisible)
        panel.hide()
        #expect(!panel.isVisible)
    }
}
