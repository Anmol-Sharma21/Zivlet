import AppKit
import ZivletCore
import ZivletShelfCore

extension BoxController {
    /// The value the views draw.
    public var viewModel: BoxViewModel {
        let items = (current?.items ?? []).map { item in
            BoxItemModel(id: item.id, name: item.displayName, bytes: item.byteCount, status: statuses[item.id])
        }
        let placeholders = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, images[$0.id] ?? thumbnails.placeholder(forName: $0.name)) })
        return BoxViewModel(
            items: items, selection: selection.selected, presentation: presentation,
            viewMode: current?.viewMode ?? .grid, finish: ports.finish(), images: placeholders,
            maxHeight: CGFloat(PanelFrames.maxHeight(in: display(for: current?.frame))),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// A press in the panel or the tray.
    public func press(_ press: BoxPress) {
        switch press {
        case .grid: setViewMode(.grid)
        case .list: setViewMode(.list)
        case .openPanel: openFromSmall()
        case .confirm(let yes): apply(.confirmAnswered(yes))
        case .select(let id, let extend, let toggle):
            select(selection.clicking(id, extend: extend, toggle: toggle, in: order))
        case .clearSelection: select(selection.cleared())
        case .marquee(let rect):
            let hit = GridSelection.marquee(rect, cells: BoxGrid.cells(count: order.count)).map { order[$0] }
            select(GridSelection(selected: Set(hit), anchor: hit.first, focus: hit.last))
        case .more: break
        case .cancelBusy: onBulk(.cancelBusy, [])
        case .share: share()
        case .airDrop: airDrop()
        case .copy: copyItems()
        case .copyPaths: copyPaths(shellQuoted: actions.optionHeld())
        case .moveTo: moveItems()
        case .copyTo: copyItemsTo()
        case .trash, .remove, .clear, .locate, .removeMissing:
            onBulk(press, targets())
        }
    }

    /// 17e §2.3's keys while the panel is key; false hands the key back to AppKit.
    public func handleKey(_ stroke: BoxKeyStroke) -> Bool {
        guard let command = BoxKeyMap.command(for: stroke) else { return false }
        run(command)
        return true
    }

    func run(_ command: BoxCommand) {
        switch command {
        case .selectAll: select(selection.all(order))
        case .move(let direction, let extend):
            let columns = current?.viewMode == .list ? 1 : BoxLook.Grid.columns
            select(selection.moving(direction, extend: extend, in: order, columns: columns))
        case .quickLook: showQuickLook()
        case .copy: copyItems()
        case .copyPaths: copyPaths(shellQuoted: false)
        case .moveTo: moveItems()
        case .copyTo: copyItemsTo()
        case .share: share()
        case .remove: onBulk(.remove, targets())
        case .trash: onBulk(.trash, targets())
        case .newBox: makeNewBox()
        case .grid: setViewMode(.grid)
        case .list: setViewMode(.list)
        case .collapse: apply(.escape)
        case .type(let characters): typeSelect(characters)
        }
    }

    var order: [UUID] { current?.items.map(\.id) ?? [] }

    private func select(_ next: GridSelection) {
        selection = next
        render()
    }

    private func setViewMode(_ mode: Shelf.ViewMode) {
        guard let shelf = current, shelf.viewMode != mode else { return }
        library = library.replacing(shelf.showing(mode))
        save()
        render()
    }

    private func openFromSmall() {
        switch presentation.base {
        case .docked, .collapsed: apply(.click)
        case .hidden, .expanded: showPanel()
        }
    }

    private func typeSelect(_ characters: String) {
        typed = typed.typing(characters, at: ports.uptime())
        let names = (current?.items ?? []).map { ($0.id, $0.displayName) }
        guard let match = typed.match(in: names) else { return }
        select(GridSelection(selected: [match], anchor: match, focus: match))
    }

    /// Quick Look of the selection (or every item) that is on this Mac now; the panel takes the keyboard as a click
    /// would (prototype: key without activating).
    private func showQuickLook() {
        let urls = targets().compactMap { item -> URL? in
            switch statuses[item.id] {
            case .present(let path): URL(filePath: path)
            case nil: URL(filePath: item.lastKnownPath)
            case .inTrash, .volumeOffline, .missing: nil
            }
        }
        guard !urls.isEmpty else { return }
        panel.makeKey()
        ports.quickLook.preview(urls)
    }

    private func makeNewBox() {
        do {
            replace(try library.adding([], to: .newBox, now: ports.now()).0)
        } catch {
            onError(error.userMessage)
        }
    }
}
