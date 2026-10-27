import AppKit
import Foundation
import UniformTypeIdentifiers

/// Thumbnails for the box (D-M5b-14, 19c D-BL11). A cell first shows the system icon for its item's type, which needs
/// only the name; Quick Look's thumbnail follows for visible items only, at most four requests at a time, cached by
/// item and size (the one place images live, so the count limit bounds them). Each size has its own visible set (the
/// panel's cells, the tray's strip); an item that leaves it loses its request, waiting or running. Two requests for
/// the same item and size share one Quick Look request.
public final class ThumbnailCache {
    public static let maxConcurrent = 4
    public static let countLimit = 400

    struct Key: Hashable {
        let id: UUID
        let size: ThumbnailSize
    }

    private let maker: any ThumbnailMaking
    private let limit: Int
    private let scale: Double
    private let images: any ThumbnailStoring
    private var icons: [String: NSImage] = [:]
    private var visible: [ThumbnailSize: Set<UUID>] = [:]
    private var running = 0
    private var waiting: [(key: Key, gate: CheckedContinuation<Bool, Never>)] = []
    private var requests: [Key: Task<NSImage?, Never>] = [:]

    public init(
        maker: any ThumbnailMaking, maxConcurrent: Int = ThumbnailCache.maxConcurrent,
        scale: Double = Double(NSScreen.main?.backingScaleFactor ?? 2),
        store: any ThumbnailStoring = SystemThumbnailStore()
    ) {
        self.maker = maker
        limit = max(1, maxConcurrent)
        self.scale = scale
        images = store
    }

    /// The system icon for the type the name's extension stands for; no file is read.
    public func placeholder(forName name: String) -> NSImage {
        let ext = (name as NSString).pathExtension.lowercased()
        if let icon = icons[ext] { return icon }
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        let icon = NSWorkspace.shared.icon(for: type)
        icons[ext] = icon
        return icon
    }

    public func cached(_ id: UUID, size: ThumbnailSize) -> NSImage? { images.object(forKey: Self.key(id, size)) }

    /// The items on screen now at `size`; requests for every other item at that size are cancelled.
    public func setVisible(_ ids: Set<UUID>, size: ThumbnailSize = .cell) {
        visible[size] = ids
        let gone = { (key: Key) in key.size == size && !ids.contains(key.id) }
        let dropped = waiting.filter { gone($0.key) }
        waiting.removeAll { gone($0.key) }
        dropped.forEach { $0.gate.resume(returning: false) }
        for (key, task) in requests where gone(key) { task.cancel() }
    }

    /// Quick Look's thumbnail for a visible item, from the cache when it has one; nil for text, when the item is not
    /// visible, leaves the visible set, or Quick Look has none. Cancelling the caller cancels the request.
    public func thumbnail(for id: UUID, url: URL, size: ThumbnailSize) async -> NSImage? {
        guard Self.asksQuickLook(url) else { return nil }
        if let hit = cached(id, size: size) { return hit }
        let key = Key(id: id, size: size)
        guard isVisible(key) else { return nil }
        let request = requests[key] ?? start(key, url: url)
        return await withTaskCancellationHandler {
            await request.value
        } onCancel: {
            request.cancel()
        }
    }

    /// Text of any kind keeps its type icon (owner, 2026-10-26): Quick Look's white page was the brightest thing on
    /// the dark glass (G-M5b-14). Decided from the name, so no file is read.
    static func asksQuickLook(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return true }
        return !type.conforms(to: .text)
    }

    private func start(_ key: Key, url: URL) -> Task<NSImage?, Never> {
        let task = Task { [weak self] () -> NSImage? in
            guard let self else { return nil }
            defer { requests[key] = nil }
            return await make(key, url: url)
        }
        requests[key] = task
        return task
    }

    private func make(_ key: Key, url: URL) async -> NSImage? {
        guard await acquire(key) else { return nil }
        defer { release() }
        guard isVisible(key), !Task.isCancelled else { return nil }
        let made = await maker.thumbnail(for: url, side: key.size.side, scale: scale)
        guard let made, isVisible(key), !Task.isCancelled else { return nil }
        let image = NSImage(cgImage: made, size: NSSize(width: key.size.side, height: key.size.side))
        images.setObject(image, forKey: Self.key(key.id, key.size))
        return image
    }

    private func isVisible(_ key: Key) -> Bool { visible[key.size]?.contains(key.id) ?? false }

    private func acquire(_ key: Key) async -> Bool {
        guard running >= limit else {
            running += 1
            return true
        }
        return await withCheckedContinuation { waiting.append((key, $0)) }
    }

    /// Hands the slot to the next waiting request, or frees it.
    private func release() {
        guard !waiting.isEmpty else {
            running -= 1
            return
        }
        waiting.removeFirst().gate.resume(returning: true)
    }

    private static func key(_ id: UUID, _ size: ThumbnailSize) -> NSString {
        "\(id.uuidString)-\(size.rawValue)" as NSString
    }
}
