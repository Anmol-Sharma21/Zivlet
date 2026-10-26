import AppKit
import ZivletShelfCore

/// Turns a drop into box items (P2-141, D-M5b-4, D-M5b-5). Before the drop only the pasteboard's item count is read,
/// for "Add 3"; nothing touches the files. At the drop: file URLs become references (validated: file URLs only, not
/// inside the box's own storage, once each); otherwise file promises are received into the box's folder; otherwise
/// text or an image becomes an owned clipping.
public struct BoxIntake {
    static let insideStorage = "is already kept by the Drop Box."
    static let textClipping = "Clipping.txt"
    static let imageClipping = "Clipping.png"

    private let maker: any BookmarkMaking
    private let storage: OwnedStorage
    private let promises: any PromiseReceiving
    private let now: () -> Date

    public init(
        maker: any BookmarkMaking, storage: OwnedStorage, promises: any PromiseReceiving,
        now: @escaping () -> Date = Date.init
    ) {
        self.maker = maker
        self.storage = storage
        self.promises = promises
        self.now = now
    }

    /// The pasteboard's item count, without reading any file (D-M5b-4).
    public func preview(_ pasteboard: NSPasteboard) -> Int { pasteboard.pasteboardItems?.count ?? 0 }

    public func receive(from pasteboard: NSPasteboard, box: UUID) async -> IntakeResult {
        let urls = Self.fileURLs(on: pasteboard)
        if !urls.isEmpty { return references(urls) }
        if promises.hasPromises(on: pasteboard) { return await promised(pasteboard, box: box) }
        if let clipping = clipping(from: pasteboard, box: box) { return clipping }
        return IntakeResult(items: [], rejected: [IntakeResult.nothingUsable], ownedBytes: 0)
    }

    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        return (objects as? [URL] ?? []).filter(\.isFileURL)
    }

    private func references(_ urls: [URL]) -> IntakeResult {
        var seen: Set<String> = []
        var items: [ShelfItem] = []
        var rejected: [String] = []
        for url in urls.map(\.standardizedFileURL) where seen.insert(url.path).inserted {
            guard storage.relativePath(of: url) == nil else {
                rejected.append("\(url.lastPathComponent) \(Self.insideStorage)")
                continue
            }
            do {
                items.append(try ShelfItem.referencing(url, using: maker, now: now()))
            } catch {
                rejected.append("\(url.lastPathComponent): \(error.userMessage)")
            }
        }
        return IntakeResult(items: items, rejected: rejected, ownedBytes: 0)
    }

    private func promised(_ pasteboard: NSPasteboard, box: UUID) async -> IntakeResult {
        let folder: URL
        do {
            folder = try storage.makeFolder(for: box)
        } catch {
            return IntakeResult(items: [], rejected: [error.userMessage], ownedBytes: 0)
        }
        let outcome = await promises.receivePromises(from: pasteboard, into: folder)
        let owned = outcome.received.map(owning)
        let failures = Array(repeating: ShelfError.bookmarkFailed.userMessage, count: outcome.failed)
        return Self.result(owned, extraRejected: failures)
    }

    private func clipping(from pasteboard: NSPasteboard, box: UUID) -> IntakeResult? {
        if let text = pasteboard.string(forType: .string) {
            return Self.result([write(Data(text.utf8), name: Self.textClipping, box: box)])
        }
        guard let image = (pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first,
            let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(
                using: .png, properties: [:])
        else { return nil }
        return Self.result([write(png, name: Self.imageClipping, box: box)])
    }

    private func write(_ data: Data, name: String, box: UUID) -> Result<ShelfItem, ShelfError> {
        do {
            let url = try storage.reserve(name: name, in: box)
            guard
                FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
            else { return .failure(.storageFailed) }
            return owning(url)
        } catch {
            return .failure(error)
        }
    }

    /// An owned copy as an item: its bookmark, its path relative to the storage root, its size.
    private func owning(_ url: URL) -> Result<ShelfItem, ShelfError> {
        guard let relative = storage.relativePath(of: url) else { return .failure(.ownedPathOutsideBox) }
        do {
            let file = url.standardizedFileURL
            return .success(
                try ShelfItem(
                    bookmark: maker.bookmark(for: file), lastKnownPath: file.path, displayName: file.lastPathComponent,
                    byteCount: Self.size(of: file) ?? maker.size(of: file), addedAt: now(),
                    ownership: .owned(relativePath: relative)))
        } catch {
            return .failure(error)
        }
    }

    private static func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init)
    }

    private static func result(_ results: [Result<ShelfItem, ShelfError>], extraRejected: [String] = []) -> IntakeResult
    {
        let items = results.compactMap { try? $0.get() }
        let rejected = results.compactMap { result -> String? in
            if case .failure(let error) = result { return error.userMessage }
            return nil
        }
        return IntakeResult(
            items: items, rejected: rejected + extraRejected,
            ownedBytes: items.compactMap(\.byteCount).reduce(0, +))
    }
}
