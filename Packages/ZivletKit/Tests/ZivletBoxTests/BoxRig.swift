import AppKit
import TestSupport
import Testing
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletShelfCore

@testable import ZivletBox

/// A thumbnail maker that has none: the controller tests never wait on Quick Look.
@MainActor
struct NoThumbnails: ThumbnailMaking {
    func thumbnail(for url: URL, side: Double, scale: Double) async -> CGImage? { nil }
}

@MainActor
final class FakeQuickLook: QuickLookPresenting {
    private(set) var previews: [[URL]] = []

    func preview(_ urls: [URL]) { previews.append(urls) }
}

/// One store, storage and set of fakes shared by every controller a test makes, so a second controller is a
/// relaunch. Displays sit far off screen, so panels never show on the real screen.
@MainActor
final class BoxRig {
    static let display = Rect2D(x: -8000, y: -8000, width: 1800, height: 1100)

    let dir: TempDir
    let bookmarks = FakeBoxBookmarks()
    let quickLook = FakeQuickLook()
    let picker = FakeSharePicker()
    let results = ResultLog()
    let board = TestPasteboard()
    var sharing = FakeBoxSharing()
    var optionHeld = false
    var mounted = true
    private(set) var turns = 0
    let folders: FakeBoxFolders
    let undo: UndoHistory
    var clock = 0.0
    var displays = [BoxRig.display]

    init() throws {
        dir = try TempDir(prefix: "zivlet-box-rig")
        folders = FakeBoxFolders(answer: try dir.folder("dst"))
        undo = UndoHistory(store: UndoStore(file: dir.url.appending(path: "undo.json")))
    }

    /// Where Move to… and Copy to… put items unless a test says otherwise.
    var destination: URL { dir.url.appending(path: "dst") }

    var store: BoxStore { BoxStore(file: dir.url.appending(path: "boxes.json")) }
    var storage: OwnedStorage { OwnedStorage(root: dir.url.appending(path: "Box")) }

    func controller() -> BoxController {
        let box = BoxController(
            ports: BoxPorts(
                store: store, storage: storage, maker: bookmarks, resolver: bookmarks,
                isMounted: { [unowned self] _ in mounted },
                promises: FakePromises(names: []), thumbnails: NoThumbnails(), quickLook: quickLook,
                visibleFrames: { [unowned self] in displays }, finish: { .solid },
                now: { Date(timeIntervalSince1970: 1_000) }, uptime: { [unowned self] in clock }),
            actions: actions)
        box.onResult = { [results] result, anchor in results.record(result, anchor) }
        return box
    }

    var actions: BoxActions {
        BoxActions(
            sharePicker: picker, clipboard: ClipboardAction(pasteboard: board.board),
            airDrop: AirDropAction(service: sharing), optionHeld: { [unowned self] in optionHeld },
            nextTurn: { [unowned self] in turns += 1 },
            service: ActionService(folders: folders, undoHistory: undo, nextTurn: {}))
    }

    func files(_ count: Int, prefix: String = "f") throws -> [URL] {
        try (0..<count).map { try dir.file("files/\(prefix)\($0).txt") }
    }

    /// The library as saved on disk.
    func saved() -> ShelfLibrary? {
        guard case .loaded(let library, _) = store.load() else { return nil }
        return library
    }
}
