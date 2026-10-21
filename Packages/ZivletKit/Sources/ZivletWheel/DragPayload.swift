import AppKit
import ZivletCore
import ZivletTrigger
import ZivletWheelCore

/// What is being dragged, read once per drag-pasteboard change count (03a §1.6).
public struct DragPayload: Sendable, Equatable {
    public let changeCount: Int
    public let urls: [URL]
    public let items: [SelectionItem]
    public let hubItems: [HubItem]

    public init(changeCount: Int, urls: [URL], items: [SelectionItem], hubItems: [HubItem]) {
        self.changeCount = changeCount
        self.urls = urls
        self.items = items
        self.hubItems = hubItems
    }

    /// The trigger's view: item count and the modes that have content (`DragSummary.acceptedModes`).
    public func summary(builder: SliceBuilder = SliceBuilder()) -> DragSummary {
        DragSummary(itemCount: items.count, acceptedModes: builder.acceptedModes(items: items))
    }
}

/// One URL after classification.
nonisolated public struct ClassifiedItem: Sendable, Equatable {
    public let item: SelectionItem
    public let hub: HubItem
}

/// Reads file URLs from the drag pasteboard on the main actor, then stats them off it. Results are cached by change
/// count and never replaced by an older count's result.
public final class DragPayloadReader {
    /// Items beyond this are classified by extension only (03a §1.5 probe budget).
    public nonisolated static let statLimit = 512

    public private(set) var latest: DragPayload?
    private let pasteboard: NSPasteboard
    private let registry: FormatRegistry
    private let builder: SliceBuilder

    public init(
        pasteboard: NSPasteboard = NSPasteboard(name: .drag), registry: FormatRegistry = .standard,
        builder: SliceBuilder = SliceBuilder()
    ) {
        self.pasteboard = pasteboard
        self.registry = registry
        self.builder = builder
    }

    public func read(changeCount: Int) async -> DragPayload {
        if let latest, latest.changeCount == changeCount { return latest }
        let urls = Self.fileURLs(from: pasteboard)
        let classified = await Self.classify(urls, registry: registry)
        let payload = DragPayload(
            changeCount: changeCount, urls: urls, items: classified.map(\.item), hubItems: classified.map(\.hub))
        if changeCount >= (latest?.changeCount ?? .min) { latest = payload }
        return payload
    }

    /// The trigger host's payload probe.
    public func summary(changeCount: Int) async -> DragSummary {
        await read(changeCount: changeCount).summary(builder: builder)
    }

    /// File URLs only; web links and text on the same pasteboard are ignored.
    public static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return (objects ?? []).compactMap { $0 as? URL }
    }

    @concurrent
    nonisolated static func classify(_ urls: [URL], registry: FormatRegistry) async -> [ClassifiedItem] {
        urls.enumerated().map { index, url in
            classify(url, stat: index < statLimit, registry: registry)
        }
    }

    private nonisolated static func classify(_ url: URL, stat: Bool, registry: FormatRegistry) -> ClassifiedItem {
        let name = url.lastPathComponent
        let format = registry.formatID(fileName: name)
        guard stat else { return item(format, .file, isLocal: true, bytes: nil, name: name) }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .volumeIsLocalKey]
        do {
            let values = try url.resourceValues(forKeys: keys)
            let kind: SelectionItemKind =
                values.isDirectory == true ? (values.isPackage == true ? .package : .folder) : .file
            let bytes = kind == .file ? values.fileSize.map(Int64.init) : nil
            return item(
                kind == .folder ? nil : format, kind, isLocal: values.volumeIsLocal ?? true, bytes: bytes, name: name)
        } catch {
            // Unreadable or gone: the wheel shows "Zivlet can't read one of these files".
            return item(format, .file, isLocal: false, bytes: nil, name: name)
        }
    }

    private nonisolated static func item(
        _ format: FormatID?, _ kind: SelectionItemKind, isLocal: Bool, bytes: Int64?, name: String
    ) -> ClassifiedItem {
        ClassifiedItem(
            item: SelectionItem(format, kind: kind, isLocal: isLocal),
            hub: HubItem(name: name, format: format, kind: kind, byteCount: bytes))
    }
}
