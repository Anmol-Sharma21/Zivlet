import AppKit
import Testing

@testable import ZivletActions

@Suite("Share picker (P2-142): the system picker, kept alive until it reports")
@MainActor
struct SharePickerTests {
    @Test func nothingToShareShowsNothing() {
        let picker = SystemSharePicker()
        picker.show([], relativeTo: .zero, of: NSView(), edge: .minY)
        #expect(!picker.isShowing)
    }

    @Test func aChoiceOrADismissalLetsThePickerGo() {
        let picker = SystemSharePicker()
        let system = NSSharingServicePicker(items: [URL(filePath: "/tmp/a.txt")])
        picker.hold(system)
        #expect(picker.isShowing)
        picker.sharingServicePicker(system, didChoose: nil)
        #expect(!picker.isShowing)
    }
}
