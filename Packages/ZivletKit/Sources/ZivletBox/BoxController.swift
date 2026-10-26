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
    var images: [UUID: NSImage] = [:]
    var resolvedBox: UUID?
    var requestedThumbnails: Set<UUID> = []
    var canSave = true

    /// A bulk action on its targets (the selection, else every item); stream C runs them.
    public var onBulk: (BoxPress, [ShelfItem]) -> Void = { _, _ in }
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

    public init(ports: BoxPorts, actions: BoxActions = BoxActions()) {
        self.ports = ports
        self.actions = actions
        intake = BoxIntake(maker: ports.maker, storage: ports.storage, promises: ports.promises, now: ports.now)
        thumbnails = ThumbnailCache(maker: ports.thumbnails)
        wirePanel()
    }

    public var current: Shelf? { library.current }

    /// The system icon for a name's type; no file is read.
    public func placeholder(forName name: String) -> NSImage { thumbnails.placeholder(forName: name) }

    /// Loads the boxes and restores the panel as it was, without resolving anything.
    public func start() {
        switch ports.store.load() {
        case .loaded(let loaded, _): library = loaded
        case .newer:
            canSave = false
            onError(BoxStoreError.wouldOverwriteNewer.userMessage)
        case .empty, .damaged: break
        }
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

    /// Saves the library and the panel's state; called when Zivlet quits.
    public func quit() { persist() }

    public func dock(_ edge: DockEdge) { apply(.dock(edge)) }

    /// Adds files to the current box, or to a new one (⌥ on BOX, or the setting).
    public func add(_ urls: [URL], newBox: Bool) async -> AddOutcome {
        let local = urls.filter(\.isFileURL)
        guard !local.isEmpty else { return AddOutcome(added: 0, failure: IntakeResult.nothingUsable) }
        return store(intake.references(local), newBox: newBox)
    }

    /// A drop on the panel, inside `performDragOperation`.
    public func receiveDrop(_ pasteboard: NSPasteboard) async -> AddOutcome {
        let result = await intake.receive(from: pasteboard, box: library.current?.id ?? UUID())
        let outcome = store(result, newBox: false)
        apply(.dropped)
        return outcome
    }

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
            case .present: resolveIfNeeded()
            case .dismiss:
                resolvedBox = nil
                requestedThumbnails = []
            case .persist: persist()
            case .confirmed(let kind): onBulk(kind == .clear ? .clear : .trash, targets())
            case .cancelBusy: onBulk(.cancelBusy, [])
            }
        }
        render()
    }

    func store(_ result: IntakeResult, newBox: Bool) -> AddOutcome {
        guard !result.items.isEmpty else {
            return AddOutcome(added: 0, rejected: result.rejected, failure: result.rejected.first)
        }
        do {
            let (next, report) = try library.adding(result.items, to: newBox ? .newBox : .current, now: ports.now())
            replace(next)
            return AddOutcome(
                added: report.added.count, duplicates: report.duplicates + report.overCap,
                rejected: result.rejected)
        } catch {
            return AddOutcome(added: 0, rejected: result.rejected, failure: error.userMessage)
        }
    }

    /// A new library: saved, the counts given to the presentation, the selection kept to what is left.
    func replace(_ next: ShelfLibrary) {
        if next.currentID != library.currentID { resolvedBox = nil }
        library = next
        save()
        selection = selection.keeping(current?.items.map(\.id) ?? [])
        let missing = current?.items.filter { !(statuses[$0.id]?.isAvailable ?? true) }.count ?? 0
        apply(.itemsChanged(count: current?.items.count ?? 0, missing: missing))
        onChange()
    }

    /// Resolves the current box once per show (P2-141 lazy resolution) and saves refreshed bookmarks.
    func resolveIfNeeded() {
        guard let shelf = current, resolvedBox != shelf.id else { return }
        resolvedBox = shelf.id
        let resolved = shelf.resolving(with: ports.resolver, maker: ports.maker, isMounted: ports.isMounted)
        statuses = resolved.statuses
        if resolved.shelf != shelf {
            library = library.replacing(resolved.shelf)
            save()
        }
        presentation =
            presentation.handling(
                .itemsChanged(count: resolved.shelf.items.count, missing: resolved.missingCount)
            ).0
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

    func save() {
        guard canSave else { return }
        do {
            try ports.store.save(library)
        } catch {
            Self.logger.error("Drop Box not saved")
            onError(error.userMessage)
        }
    }

    /// The selection's items, or every item when nothing is selected.
    func targets() -> [ShelfItem] {
        let items = current?.items ?? []
        return selection.selected.isEmpty ? items : items.filter { selection.selected.contains($0.id) }
    }
}
