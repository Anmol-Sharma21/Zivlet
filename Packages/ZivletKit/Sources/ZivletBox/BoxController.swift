import AppKit
import SwiftUI
import ZivletActions
import ZivletCore
import ZivletShelfCore
import os

/// The Drop Box on screen (P2-55, P2-141): owns the library, the store, the panel, its presentation and the
/// thumbnails. The BOX slice, the panel and the tray all add through it. Nothing is resolved at launch; the current
/// box is resolved when the panel shows its items, stale bookmarks are refreshed and saved.
public final class BoxController {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")

    let ports: BoxPorts
    let actions: BoxActions
    let intake: BoxIntake
    let thumbnails: ThumbnailCache
    public let panel = BoxPanel()
    let dropView = BoxDropView()
    let hosting = NSHostingView(rootView: AnyView(EmptyView()))

    public internal(set) var library = ShelfLibrary()
    public internal(set) var presentation = BoxPresentation()
    var statuses: [UUID: ItemStatus] = [:]
    var selection = GridSelection()
    var typed = TypeSelect()
    var resolvedBox: UUID?
    /// The exit fade running now (G-M5b-10); a show during it cancels it, and a stale completion does nothing.
    var fading: UUID?
    /// The resolution of the shown box, running off the main thread (G-M5b-8).
    var resolving: Task<Void, Never>?
    /// The cells on screen now (their `onAppear` and `onDisappear`): the only items whose thumbnails are asked for.
    var onScreen: Set<UUID> = []
    /// One redraw for every thumbnail that arrives in the same turn.
    var thumbnailRedraw: Task<Void, Never>?
    /// Redraws the tray's compact view when one of its thumbnails arrives.
    var trayRedraw: (() -> Void)?
    /// The last model drawn and how many draws there were, for the tests.
    var rendered: BoxViewModel?
    var renders = 0
    var canSave = true
    /// The library as last written or read, so an unchanged library is not written again.
    var lastSaved: ShelfLibrary?
    /// The last save error told to the person; the same error is not told again until a save works.
    var lastSaveError: BoxStoreError?
    /// The bulk action in flight (AirDrop, Move, Copy to, Locate), so tests and the next action can wait for it.
    var running: Task<Void, Never>?
    /// Move to Trash of more than one item, waiting for the inline answer.
    var pendingTrash: BulkTargets?
    /// Recent Moves to Trash whose items Undo can put back, newest last.
    var trashBatches: [TrashBatch] = []
    /// The last Clear, while its Undo still works, and the wait that ends it.
    var pendingClear: PendingClear?
    var clearing: Task<Void, Never>?
    /// Bytes of every box's owned copies, from their items' sizes (no walk of the folder on the main thread).
    var ownedBytes: Int64 = 0

    /// When items leave the box on their own (Settings › Drop Box); off until the app says otherwise.
    public var autoClear: () -> AutoClear = { .off }

    /// A bulk action finished: its result for the toast or the card, and the panel's frame as the anchor.
    public var onResult: (ActionResult, CGRect?) -> Void = { _, _ in }
    /// The library or the presentation changed (the menu and the tray follow it).
    public var onChange: () -> Void = {}
    /// A save failed: the sentence to show.
    public var onError: (String) -> Void = { _ in }
    /// A drop on the panel finished: what it added, for the toast.
    public var onAdded: (AddOutcome) -> Void = { _ in }
    /// The panel's base or frame changed (nil when it is off screen): for the log the demo scripts read.
    public var onPresented: (BoxPresentation.Base, CGRect?) -> Void = { _, _ in }
    var lastReport: (base: BoxPresentation.Base, frame: CGRect?)?

    public init(ports: BoxPorts, actions: BoxActions) {
        self.ports = ports
        self.actions = actions
        intake = BoxIntake(maker: ports.maker, storage: ports.storage, promises: ports.promises, now: ports.now)
        thumbnails = ThumbnailCache(maker: ports.thumbnails, store: ports.thumbnailStore())
        wirePanel()
        actions.sharePicker.onFailure = { [weak self] in self?.report(.failed(ActionCard(title: BoxCopy.sharingFailed)))
        }
    }

    public var current: Shelf? { library.current }

    /// The system icon for a name's type; no file is read.
    public func placeholder(forName name: String) -> NSImage { thumbnails.placeholder(forName: name) }

    /// Loads the boxes and restores the panel as it was, without resolving anything. A load that lost something or
    /// set the file aside says so; only a clean load sweeps copies no item points at (a crash in Clear's window).
    public func start() {
        let load = ports.store.load()
        if case .loaded(let loaded, let dropped) = load {
            library = loaded
            if dropped == 0 {
                lastSaved = loaded
                sweepStrays()
            }
        }
        canSave = load.canSave
        if let notice = load.notice { onError(notice) }
        clearAutomatically(left: [])
        refreshStorage()
        let shelf = library.current
        presentation = BoxPresentation(
            base: shelf?.shown ?? .hidden, dock: shelf?.dock, missing: 0, isEmpty: shelf?.items.isEmpty ?? true)
        if presentation.base == .expanded { resolveIfNeeded() }
        render()
    }

    /// The menu command, the BOX slice, shake or the tray: the full box at its anchor.
    public func showPanel(_ anchor: BoxAnchor = .saved) {
        place(anchor)
        var (next, effects) = presentation.handling(.show)
        if next.base != .expanded {
            let (expanded, more) = next.handling(.show)
            next = expanded
            effects += more.filter { !effects.contains($0) }
        }
        commit(next, effects)
    }

    public func hidePanel() { apply(.hide) }

    /// Saves the library and the panel's state; called when Zivlet quits. A Clear still in its undo window ends now,
    /// so its owned copies do not outlive it.
    public func quit() {
        clearing?.cancel()
        if let pending = pendingClear { finishClear(pending.batch) }
        persist()
    }

    public func dock(_ edge: DockEdge) { apply(.dock(edge)) }

    public func dragEntered(count: Int) { apply(.dragEntered(count: count)) }

    public func dragExited() { apply(.dragExited) }

    /// The panel was let go after a move: dock near an edge, else float at the new frame.
    public func panelMoved(to frame: Rect2D) {
        let displays = ports.visibleFrames()
        let centre = Point2D(x: frame.midX, y: frame.midY)
        guard let display = displays.first(where: { $0.contains(centre) }) ?? displays.first else { return }
        savePlace(frame: frame)
        if let edge = DockSnapper.edge(for: frame, in: display, current: presentation.dock) {
            apply(.dock(edge))
        } else {
            apply(.undock)
        }
        persist()
        render()
    }

    // MARK: - State

    /// Runs one presentation event and its effects, then draws.
    func apply(_ event: BoxPresentationEvent) {
        let (next, effects) = presentation.handling(event)
        commit(next, effects)
    }

    /// Takes a new presentation, runs its effects and draws once.
    func commit(_ next: BoxPresentation, _ effects: [BoxPresentationEffect]) {
        presentation = next
        for effect in effects {
            switch effect {
            case .present:
                resolveIfNeeded()
                clearAutomatically(left: [])
            case .dismiss:
                resolvedBox = nil
                onScreen = []
                thumbnails.setVisible([], size: .cell)
            case .persist: persist()
            case .confirmed(let kind): confirmed(kind)
            case .cancelBusy: running?.cancel()
            }
        }
        render()
    }

    /// A new library: saved, the counts given to the presentation, the selection kept to what is left.
    func replace(_ next: ShelfLibrary) {
        if next.currentID != library.currentID { resolvedBox = nil }
        library = next
        save()
        refreshStorage()
        selection = selection.keeping(current?.items.map(\.id) ?? [])
        let missing = current?.items.filter { !(statuses[$0.id]?.isAvailable ?? true) }.count ?? 0
        apply(.itemsChanged(count: current?.items.count ?? 0, missing: missing))
        onChange()
    }

    /// Resolves the current box once per show (P2-141 lazy resolution), off the main thread: the panel draws at once
    /// with the statuses it last knew, and the new ones (and refreshed bookmarks, saved) arrive when ready.
    func resolveIfNeeded() {
        guard let shelf = current, resolvedBox != shelf.id else { return }
        resolvedBox = shelf.id
        resolve(shelf)
    }

    /// The current box with the panel's base, frame and dock, saved.
    func persist() {
        guard let shelf = current else { return }
        library = library.replacing(
            shelf.presented(presentation.base).placed(frame: shelf.frame, dock: presentation.dock))
        save()
    }

    func savePlace(frame: Rect2D) {
        guard let shelf = current else { return }
        library = library.replacing(shelf.placed(frame: frame, dock: shelf.dock))
    }

    /// Writes the library when it changed since the last write; a failure is told once until a save works again.
    func save() {
        guard canSave, library != lastSaved else { return }
        do {
            try ports.store.save(library)
            lastSaved = library
            lastSaveError = nil
        } catch {
            let reason = error == .wouldOverwriteNewer ? "a newer file is there" : "the write failed"
            Self.logger.error("Drop Box not saved: \(reason, privacy: .public)")
            guard error != lastSaveError else { return }
            lastSaveError = error
            onError(error.userMessage)
        }
    }

    /// Counts of what one resolution found, never names: why an item shows as missing can then be told from logs.
    static func logResolution(_ resolved: ResolvedShelf) {
        let missing = resolved.missingCount
        let failed = resolved.refreshFailed.count
        guard missing > 0 || failed > 0 else { return }
        logger.notice(
            "Drop Box resolved: \(missing, privacy: .public) unavailable, \(failed, privacy: .public) not refreshed")
    }

    /// The selection's items, or every item when nothing is selected.
    func targets() -> [ShelfItem] {
        let items = current?.items ?? []
        return selection.selected.isEmpty ? items : items.filter { selection.selected.contains($0.id) }
    }
}
