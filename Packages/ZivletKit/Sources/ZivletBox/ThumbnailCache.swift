import AppKit
import Foundation
import UniformTypeIdentifiers

/// Thumbnails for the box (D-M5b-14, 19c D-BL11). A cell first shows the system icon for its item's type, which needs
/// only the name; Quick Look's thumbnail follows for visible items only, at most four requests at a time, cached by
/// item and size. An item that leaves the visible set loses its request, waiting or running.
public final class ThumbnailCache {
    public static let maxConcurrent = 4
    public static let countLimit = 400

    private let maker: any ThumbnailMaking
    private let limit: Int
    private let scale: Double
    private let images = NSCache<NSString, NSImage>()
    private var icons: [String: NSImage] = [:]
    private var visible: Set<UUID> = []
    private var running = 0
    private var waiting: [(id: UUID, gate: CheckedContinuation<Bool, Never>)] = []
    private var inFlight: [UUID: Task<CGImage?, Never>] = [:]

    public init(
        maker: any ThumbnailMaking, maxConcurrent: Int = ThumbnailCache.maxConcurrent,
        scale: Double = Double(NSScreen.main?.backingScaleFactor ?? 2)
    ) {
        self.maker = maker
        limit = max(1, maxConcurrent)
        self.scale = scale
        images.countLimit = Self.countLimit
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

    /// The items on screen now; requests for every other item are cancelled.
    public func setVisible(_ ids: Set<UUID>) {
        visible = ids
        let (keep, drop) = (waiting.filter { ids.contains($0.id) }, waiting.filter { !ids.contains($0.id) })
        waiting = keep
        drop.forEach { $0.gate.resume(returning: false) }
        for (id, task) in inFlight where !ids.contains(id) { task.cancel() }
    }

    /// Quick Look's thumbnail for a visible item, from the cache when it has one; nil when the item is not visible,
    /// leaves the visible set, or Quick Look has none.
    public func thumbnail(for id: UUID, url: URL, size: ThumbnailSize) async -> NSImage? {
        if let hit = cached(id, size: size) { return hit }
        guard visible.contains(id), await acquire(id) else { return nil }
        defer { release() }
        guard visible.contains(id) else { return nil }
        let task = Task { [maker, scale] in await maker.thumbnail(for: url, side: size.side, scale: scale) }
        inFlight[id] = task
        let made = await task.value
        inFlight[id] = nil
        guard let made, visible.contains(id), !task.isCancelled else { return nil }
        let image = NSImage(cgImage: made, size: NSSize(width: size.side, height: size.side))
        images.setObject(image, forKey: Self.key(id, size))
        return image
    }

    private func acquire(_ id: UUID) async -> Bool {
        guard running >= limit else {
            running += 1
            return true
        }
        return await withCheckedContinuation { waiting.append((id, $0)) }
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
