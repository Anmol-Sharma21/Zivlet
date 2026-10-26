import AppKit
import Testing
import ZivletActions
import ZivletTriggerHost

@testable import ZivletBox

@Suite("Convert all: a drag out of the box carries files the trigger sees (17e §2.3)")
@MainActor
struct BoxConvertAllTests {
    @Test func theBoxsDragWritesFileURLsTheTriggerLooksFor() throws {
        let rig = try BoxRig()
        let files = try rig.files(3)
        let items = DragSourceView.draggingItems(for: files, frame: CGRect(x: 0, y: 0, width: 48, height: 48))
        let board = TestPasteboard()
        board.board.clearContents()
        #expect(board.board.writeObjects(items.compactMap { $0.item as? any NSPasteboardWriting }))
        #expect(SystemInputReader(pasteboard: board.board).dragHasFileTypes())
        #expect(board.board.readObjects(forClasses: [NSURL.self]) as? [URL] == files)
    }

    @Test func eachItemIsFannedFourPointsFromTheLast() {
        let urls = [URL(filePath: "/tmp/a.txt"), URL(filePath: "/tmp/b.txt")]
        let frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        let items = DragSourceView.draggingItems(for: urls, frame: frame)
        #expect(items.map(\.draggingFrame) == [frame, frame.offsetBy(dx: 4, dy: -4)])
    }
}
