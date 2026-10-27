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

/// An exit with no fade: the panel goes at once, as before G-M5b-10.
@MainActor
struct InstantFader: PanelFading {
    func fadeOut(_ panel: NSWindow, seconds: Double, completion: @escaping @MainActor @Sendable () -> Void) {
        completion()
    }
    func cancel(_ panel: NSWindow) { panel.alphaValue = 1 }
}

/// A Boolean that any thread can read and set.
nonisolated final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool

    init(_ value: Bool) { stored = value }

    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
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
    /// Whether every volume counts as mounted; read off the main thread while the box resolves.
    var mounted: Bool {
        get { mountFlag.value }
        set { mountFlag.value = newValue }
    }
    private let mountFlag = LockedFlag(true)
    private(set) var turns = 0
    let folders: FakeBoxFolders
    let trash = FakeBoxTrash()
    let locator = FakeLocator()
    /// Clear's 10 s wait: held (until the clear is undone and its task cancelled) or over at once.
    var sleepHolds = true
    private(set) var slept: [Duration] = []
    let undo: UndoHistory
    var clock = 0.0
    var now = Date(timeIntervalSince1970: 1_000)
    var displays = [BoxRig.display]
    var finish = BoxFinish.solid
    /// Quick Look for the controllers made after it is set; none by default.
    var thumbnailMaker: (any ThumbnailMaking)?
    var promises: (any PromiseReceiving)?
    /// Another bookmark maker or folder chooser for the controllers made after it is set.
    var maker: (any BookmarkMaking)?
    /// Another bookmark resolver for the controllers made after it is set (one that holds).
    var resolver: (any BookmarkResolving)?
    var chooser: (any FolderChoosing)?
    /// The panel's exit fade for the controllers made after it is set; instant by default.
    var fader: (any PanelFading)?
    var reduceMotion = false
    /// Another move executor for the controllers made after it is set (a gated rename).
    var executor: MoveExecutor?

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
                store: store, storage: storage, maker: maker ?? bookmarks, resolver: resolver ?? bookmarks,
                isMounted: { [mountFlag] _ in mountFlag.value },
                promises: promises ?? FakePromises(names: []), thumbnails: thumbnailMaker ?? NoThumbnails(),
                quickLook: quickLook, visibleFrames: { [weak self] in self?.displays ?? [BoxRig.display] },
                finish: { [weak self] in self?.finish ?? .solid },
                now: { [weak self] in self?.now ?? Date(timeIntervalSince1970: 1_000) },
                uptime: { [weak self] in self?.clock ?? 0 }, trash: trash,
                locator: locator, sleep: { [weak self] duration in await self?.wait(duration) },
                recordUndo: { [undo] batch, moves in await undo.record(batch, moves: moves) },
                fader: fader ?? InstantFader(), reduceMotion: { [weak self] in self?.reduceMotion ?? false },
                thumbnailStore: { KeptThumbnailStore() }),
            actions: actions)
        box.onResult = { [results] result, anchor in results.record(result, anchor) }
        return box
    }

    var actions: BoxActions {
        BoxActions(
            sharePicker: picker, clipboard: ClipboardAction(pasteboard: board.board),
            airDrop: AirDropAction(service: sharing), optionHeld: { [weak self] in self?.optionHeld ?? false },
            nextTurn: { [weak self] in self?.turns += 1 },
            service: ActionService(
                folders: chooser ?? folders, executor: executor ?? MoveExecutor(), undoHistory: undo, nextTurn: {}))
    }

    private func wait(_ duration: Duration) async {
        slept.append(duration)
        guard sleepHolds else { return }
        try? await Task.sleep(for: .seconds(3_600))
    }

    /// Text by default; thumbnail tests pass an image extension, since text keeps its type icon.
    func files(_ count: Int, prefix: String = "f", ext: String = "txt") throws -> [URL] {
        try (0..<count).map { try dir.file("files/\(prefix)\($0).\(ext)") }
    }

    /// The library as saved on disk.
    func saved() -> ShelfLibrary? {
        guard case .loaded(let library, _) = store.load() else { return nil }
        return library
    }
}
