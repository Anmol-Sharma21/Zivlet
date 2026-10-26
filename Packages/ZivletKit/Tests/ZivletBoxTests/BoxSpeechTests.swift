import Testing
import ZivletShelfCore

@testable import ZivletBox

@Suite("Box speech (19c §5)")
struct BoxSpeechTests {
    @Test func aPresentItemSaysNameSizeAndFolder() {
        #expect(
            BoxSpeech.item("photo.heic", bytes: 2_100_000, status: .present(path: "/Users/u/Downloads/photo.heic"))
                == "photo.heic, 2.1 MB, in Downloads")
    }

    @Test func aFolderWithoutASizeSaysOnlyWhereItIs() {
        #expect(
            BoxSpeech.item("Work", bytes: nil, status: .present(path: "/Users/u/Desktop/Work")) == "Work, in Desktop")
    }

    @Test func anUnresolvedItemSaysNameAndSize() {
        #expect(BoxSpeech.item("a.txt", bytes: 999, status: nil) == "a.txt, 999 bytes")
    }

    @Test func aMissingItemSaysSo() {
        #expect(BoxSpeech.item("photo.heic", bytes: 2_100_000, status: .missing) == "photo.heic, missing")
    }

    @Test func anItemInTheTrashSaysSo() {
        #expect(
            BoxSpeech.item("photo.heic", bytes: 1, status: .inTrash(path: "/Users/u/.Trash/photo.heic"))
                == "photo.heic, in the Trash")
    }

    @Test func anOfflineItemNamesItsVolume() {
        #expect(
            BoxSpeech.item("a.mov", bytes: nil, status: .volumeOffline(name: "Backup"))
                == "a.mov, on Backup, not connected")
    }

    @Test func theHeaderSpellsTheUnit() {
        #expect(BoxSpeech.header(count: 12, bytes: 84_000_000) == "Drop Box, 12 items, 84 megabytes")
        #expect(BoxSpeech.header(count: 1, bytes: 2_100_000) == "Drop Box, 1 item, 2.1 megabytes")
        #expect(BoxSpeech.header(count: 2, bytes: 1_500) == "Drop Box, 2 items, 1.5 kilobytes")
        #expect(BoxSpeech.header(count: 3, bytes: 1_200_000_000) == "Drop Box, 3 items, 1.2 gigabytes")
        #expect(BoxSpeech.header(count: 1, bytes: 1) == "Drop Box, 1 item, 1 byte")
        #expect(BoxSpeech.header(count: 0, bytes: 0) == "Drop Box, empty. Drop files here")
    }

    @Test func theOtherSpokenLines() {
        #expect(BoxSpeech.selection(3, of: 12) == "3 of 12 items selected")
        #expect(BoxSpeech.missing(2) == "2 items missing" && BoxSpeech.missing(1) == "1 item missing")
        #expect(BoxSpeech.dropTarget(3) == "Add 3 items to the Drop Box")
        #expect(BoxSpeech.added(1) == "Added 1 item")
    }
}

@Suite("Box copy (19c §5)")
struct BoxCopyTests {
    @Test func theVisibleLines() {
        #expect(BoxCopy.items(12) == "12 items" && BoxCopy.items(1) == "1 item")
        #expect(BoxCopy.size(84_000_000) == "84 MB" && BoxCopy.size(0) == "0 bytes")
        #expect(BoxCopy.selection(3, of: 12) == "3 of 12")
        #expect(BoxCopy.missing(2) == "2 missing")
        #expect(BoxCopy.add(3) == "Add 3" && BoxCopy.added(3) == "Added 3")
        #expect(BoxCopy.inBox(12) == "12 in box")
        #expect(BoxCopy.percent(0.4) == "40%" && BoxCopy.percent(2) == "100%")
        #expect(BoxCopy.confirm(.trash(count: 3)) == "Move 3 to Trash?" && BoxCopy.confirm(.clear) == "Clear the box?")
        #expect(BoxCopy.empty == "Drop files here")
    }

    @Test func everyPressHasItsWords() {
        for press in BoxPress.buttons { #expect(!BoxCopy.title(press).isEmpty) }
        #expect(BoxCopy.title(.moveTo) == "Move to…" && BoxCopy.title(.trash) == "Move to Trash")
        #expect(BoxCopy.title(.openPanel) == "Open Drop Box" && BoxCopy.title(.removeMissing) == "Remove Missing")
    }
}
