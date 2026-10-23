import AppKit
import Testing

@testable import ZivletUI

@Suite("Tab icon: one image per file type, so a progress redraw does not ask the workspace again (G-M5a-1)")
struct NotchIconTests {
    @Test func theSameTypeGivesTheSameImage() {
        let first = NotchIcon.image(for: "holiday.heic")
        let second = NotchIcon.image(for: "other.HEIC")
        #expect(first === second)
    }

    @Test func differentTypesGiveDifferentImages() {
        #expect(NotchIcon.image(for: "holiday.heic") !== NotchIcon.image(for: "report.pdf"))
    }
}
