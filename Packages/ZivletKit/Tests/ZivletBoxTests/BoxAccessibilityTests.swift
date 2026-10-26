import Testing
import ZivletShelfCore

@testable import ZivletBox

/// SwiftUI builds no accessibility tree without an assistive client, so the tree's text is a pure value the views
/// read; these tests check that value (19c §6).
@Suite("Box accessibility (19c §6)")
@MainActor
struct BoxAccessibilityTests {
    @Test func thePanelIsOneListWithARowPerItem() {
        let items = BoxViewFixtures.items(5, missing: 1)
        let tree = BoxAccessibility(BoxViewFixtures.model(items))
        #expect(tree.listLabel == "Drop Box, 5 items, 5 megabytes")
        #expect(tree.rows.count == 5)
        #expect(tree.rows[0] == "file-0.png, missing" && tree.rows[1] == "file-1.png, 1 MB, in Downloads")
    }

    @Test func everyButtonHasItsWords() {
        let tree = BoxAccessibility(BoxViewFixtures.model(BoxViewFixtures.items(2)))
        #expect(tree.buttons == ["Share", "AirDrop", "Copy", "Move to…", "Move to Trash"])
    }

    @Test func theListSaysWhatIsSelectedOrMissing() {
        let items = BoxViewFixtures.items(4, missing: 2)
        let tree = BoxAccessibility(BoxViewFixtures.model(items, selection: [items[3].id]))
        #expect(tree.value == "1 of 4 items selected. 2 items missing")
    }

    @Test func anEmptyBoxSaysSo() {
        let tree = BoxAccessibility(BoxViewFixtures.model([]))
        #expect(tree.listLabel == "Drop Box, empty. Drop files here" && tree.buttons.isEmpty)
    }

    @Test func theDropTargetAnnouncesTheCount() {
        let model = BoxViewFixtures.model(BoxViewFixtures.items(1), overlay: .dropTarget(count: 3))
        #expect(BoxAccessibility(model).announcement == "Add 3 items to the Drop Box")
        #expect(BoxAccessibility(BoxViewFixtures.model(BoxViewFixtures.items(1))).announcement == nil)
    }
}
