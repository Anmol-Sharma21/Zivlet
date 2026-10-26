import AppKit
import TestSupport
import Testing
import ZivletShelfCore

@testable import ZivletBox

@Suite("Box intake (P2-141 owned copies, D-M5b-4, D-M5b-5)")
@MainActor
struct BoxIntakeTests {
    private func intake(
        _ dir: TempDir, maker: any BookmarkMaking = FakeBoxBookmarks(), promises: [String] = []
    ) -> BoxIntake {
        BoxIntake(
            maker: maker, storage: OwnedStorage(root: dir.url.appending(path: "Box")),
            promises: FakePromises(names: promises), now: { Date(timeIntervalSince1970: 1_000) })
    }

    @Test func twoHundredFilesBecomeTwoHundredItems() async throws {
        let dir = try TempDir()
        let urls = try (0..<200).map { try dir.file("f\($0).txt") }
        let pasteboard = TestPasteboard(urls: urls)
        let result = await intake(dir).receive(from: pasteboard.board, box: UUID())
        #expect(result.items.count == 200 && result.rejected.isEmpty && result.ownedBytes == 0)
        #expect(result.items.allSatisfy { !$0.isOwned })
    }

    @Test func thePreviewReadsOnlyThePasteboard() throws {
        let dir = try TempDir()
        let board = TestPasteboard(urls: [URL(filePath: "/Users/u/Downloads/a.txt"), URL(filePath: "/tmp/b.txt")])
        #expect(intake(dir, maker: FailingBookmarks()).preview(board.board) == 2)
        #expect(intake(dir, maker: FailingBookmarks()).preview(TestPasteboard().board) == 0)
    }

    @Test func aFileInsideTheBoxStorageIsRefused() async throws {
        let dir = try TempDir()
        let inside = try dir.file("Box/\(UUID().uuidString)/Clipping.txt")
        let outside = try dir.file("keep.txt")
        let pasteboard = TestPasteboard(urls: [inside, outside])
        let result = await intake(dir).receive(from: pasteboard.board, box: UUID())
        #expect(result.items.map(\.displayName) == ["keep.txt"])
        #expect(result.rejected == ["Clipping.txt is already kept by the Drop Box."])
    }

    @Test func theSameFileTwiceIsOneItem() async throws {
        let dir = try TempDir()
        let file = try dir.file("a.txt")
        let twice = [file, URL(filePath: file.path + "/../a.txt")]
        let pasteboard = TestPasteboard(urls: twice)
        let result = await intake(dir).receive(from: pasteboard.board, box: UUID())
        #expect(result.items.count == 1)
    }

    @Test func promisesGoThroughThePortIntoTheBoxFolder() async throws {
        let dir = try TempDir()
        let box = UUID()
        let pasteboard = TestPasteboard()
        let result = await intake(dir, promises: ["mail.eml", "photo.jpg"]).receive(from: pasteboard.board, box: box)
        #expect(result.items.map(\.displayName) == ["mail.eml", "photo.jpg"])
        #expect(result.items.allSatisfy(\.isOwned) && result.ownedBytes == 16)
        #expect(result.items.first?.ownership == .owned(relativePath: "\(box.uuidString)/mail.eml"))
    }

    @Test func textBecomesAnOwnedClipping() async throws {
        let dir = try TempDir()
        let pasteboard = TestPasteboard(string: "hello")
        let result = await intake(dir).receive(from: pasteboard.board, box: UUID())
        #expect(result.items.map(\.displayName) == ["Clipping.txt"] && result.items.first?.isOwned == true)
        #expect(result.ownedBytes == 5)
    }

    @Test func anImageBecomesAnOwnedPNG() async throws {
        let dir = try TempDir()
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let pasteboard = TestPasteboard(image: image)
        let result = await intake(dir).receive(from: pasteboard.board, box: UUID())
        #expect(result.items.map(\.displayName) == ["Clipping.png"] && (result.ownedBytes) > 0)
    }

    @Test func nothingUsableSaysWhy() async throws {
        let dir = try TempDir()
        let pasteboard = TestPasteboard()
        let result = await intake(dir).receive(from: pasteboard.board, box: UUID())
        #expect(result.items.isEmpty && result.rejected == [IntakeResult.nothingUsable])
    }
}

@Suite("Box drop view (registration, preview, perform)")
@MainActor
struct BoxDropViewTests {
    @Test func itTakesFilesPromisesAndClippings() {
        let types = Set(BoxDropView().registeredDraggedTypes)
        #expect(types.isSuperset(of: [.fileURL, .string, .png, .tiff]))
        #expect(
            types.isSuperset(
                of: Set(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })))
    }

    @Test func enteringReportsTheCountAndAcceptsOnlyWhenAsked() throws {
        let view = BoxDropView()
        let board = TestPasteboard(urls: [URL(filePath: "/tmp/a"), URL(filePath: "/tmp/b")])
        var counts: [Int] = []
        view.onEnter = { counts.append($0) }
        view.accepts = { false }
        let info = FakeDraggingInfo(pasteboard: board.board)
        #expect(view.draggingEntered(info) == [])
        view.accepts = { true }
        #expect(view.draggingUpdated(info) == .copy)
        view.draggingExited(info)
        #expect(counts == [2, 2])
    }

    @Test func performingHandsThePasteboardOver() {
        let view = BoxDropView()
        let board = TestPasteboard(urls: [URL(filePath: "/tmp/a")])
        var received: [NSPasteboard] = []
        var exits = 0
        view.onExit = { exits += 1 }
        view.onDrop = { received.append($0) }
        view.accepts = { true }
        #expect(view.prepareForDragOperation(FakeDraggingInfo(pasteboard: board.board)))
        #expect(view.performDragOperation(FakeDraggingInfo(pasteboard: board.board)))
        #expect(received.count == 1 && exits == 0)
        view.accepts = { false }
        #expect(!view.performDragOperation(FakeDraggingInfo(pasteboard: board.board)))
    }
}

@Suite("System promise receiver without a drag session")
@MainActor
struct SystemPromiseReceiverTests {
    @Test func aPasteboardWithoutPromisesHasNone() async throws {
        let pasteboard = TestPasteboard(string: "text")
        let receiver = SystemPromiseReceiver()
        #expect(!receiver.hasPromises(on: pasteboard.board))
        let outcome = await receiver.receivePromises(from: pasteboard.board, into: try TempDir().url)
        #expect(outcome == PromiseOutcome(received: [], failed: 0))
    }
}
