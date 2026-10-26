import AppKit
import ZivletShelfCore

/// One item as the views draw it: name, size and status (nil until the box was resolved), no file access.
public struct BoxItemModel: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let bytes: Int64?
    public let status: ItemStatus?

    public init(id: UUID, name: String, bytes: Int64?, status: ItemStatus?) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.status = status
    }

    /// Unresolved items count as available until resolution says otherwise.
    public var isAvailable: Bool { status?.isAvailable ?? true }

    /// The file's URL when it is present; what a drag out carries.
    public var url: URL? {
        guard case .present(let path) = status else { return nil }
        return URL(filePath: path)
    }

    /// The badge's symbol for an item that cannot be used (19c D-BL8).
    public var badge: String? {
        switch status {
        case .missing: BoxSymbols.badgeMissing
        case .inTrash: BoxSymbols.badgeTrash
        case .volumeOffline: BoxSymbols.badgeOffline
        case .present, nil: nil
        }
    }

    public var spoken: String { BoxSpeech.item(name, bytes: bytes, status: status) }
}

/// What a press in the box asks for. The views only report presses; the controller decides.
public enum BoxPress: Sendable, Equatable {
    case share, airDrop, copy, moveTo, copyTo, copyPaths, trash, remove, clear, more
    case grid, list, openPanel, locate, removeMissing, cancelBusy
    case confirm(Bool)
    /// A click on an item: ⇧ extends the range, ⌘ toggles the item.
    case select(UUID, extend: Bool, toggle: Bool)
    case clearSelection

    /// The five icon buttons of the action bar (19c D-BL5).
    public static let bar: [BoxPress] = [.share, .airDrop, .copy, .moveTo, .trash]
    /// The overflow menu's commands.
    public static let overflow: [BoxPress] = [.copyTo, .copyPaths, .remove, .clear]
    /// Every press with words, for the copy test.
    public static let buttons: [BoxPress] =
        bar + overflow + [.more, .grid, .list, .openPanel, .locate, .removeMissing, .cancelBusy, .confirm(true)]

    var symbol: String {
        switch self {
        case .share: BoxSymbols.share
        case .airDrop: BoxSymbols.airDrop
        case .copy: BoxSymbols.copy
        case .moveTo: BoxSymbols.moveTo
        case .copyTo: BoxSymbols.copyTo
        case .copyPaths: BoxSymbols.copyPaths
        case .trash: BoxSymbols.trash
        case .remove: BoxSymbols.remove
        case .clear: BoxSymbols.clear
        case .more: BoxSymbols.more
        case .grid: BoxSymbols.grid
        case .list: BoxSymbols.list
        case .openPanel: BoxSymbols.openPanel
        case .locate: BoxSymbols.locate
        case .removeMissing: BoxSymbols.removeMissing
        case .cancelBusy: BoxSymbols.cancel
        case .confirm(let yes): yes ? BoxSymbols.trash : BoxSymbols.close
        case .select, .clearSelection: BoxSymbols.box
        }
    }
}

/// Everything the box's views draw, as one immutable value (19c §4): items, selection, presentation, view mode,
/// finish, thumbnails and the tallest the panel may grow.
public struct BoxViewModel {
    public let items: [BoxItemModel]
    public let selection: Set<UUID>
    public let presentation: BoxPresentation
    public let viewMode: Shelf.ViewMode
    public let finish: BoxFinish
    public let images: [UUID: NSImage]
    public let maxHeight: CGFloat
    public let reduceMotion: Bool

    public init(
        items: [BoxItemModel], selection: Set<UUID>, presentation: BoxPresentation, viewMode: Shelf.ViewMode,
        finish: BoxFinish, images: [UUID: NSImage] = [:], maxHeight: CGFloat, reduceMotion: Bool = false
    ) {
        self.items = items
        self.selection = selection.intersection(items.map(\.id))
        self.presentation = presentation
        self.viewMode = viewMode
        self.finish = finish
        self.images = images
        self.maxHeight = maxHeight
        self.reduceMotion = reduceMotion
    }

    public var totalBytes: Int64 { items.compactMap(\.bytes).reduce(0, +) }
    public var selected: [BoxItemModel] { items.filter { selection.contains($0.id) } }
    public var missingCount: Int { items.filter { !$0.isAvailable }.count }

    /// "12 items", or "3 of 12" with a selection.
    public var primaryLine: String {
        selection.isEmpty ? BoxCopy.items(items.count) : BoxCopy.selection(selection.count, of: items.count)
    }

    /// The size of the selection or of the box.
    public var secondaryLine: String {
        BoxCopy.size(selection.isEmpty ? totalBytes : selected.compactMap(\.bytes).reduce(0, +))
    }

    /// "2 missing" when any items cannot be used (19c §4.1 Attention).
    public var missingLine: String? { missingCount > 0 ? BoxCopy.missing(missingCount) : nil }

    /// The items a drag out carries: the selection when there is one, else every present item.
    public var dragURLs: [URL] { (selection.isEmpty ? items : selected).compactMap(\.url) }

    /// One missing item is selected: Locate… applies.
    public var canLocate: Bool { selected.count == 1 && selected.first?.isAvailable == false }

    public func with(images: [UUID: NSImage]) -> BoxViewModel {
        BoxViewModel(
            items: items, selection: selection, presentation: presentation, viewMode: viewMode, finish: finish,
            images: images, maxHeight: maxHeight, reduceMotion: reduceMotion)
    }
}
