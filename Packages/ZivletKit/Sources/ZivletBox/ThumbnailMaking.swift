import AppKit
import CoreGraphics
import Foundation
import QuickLookThumbnailing

/// Makes one thumbnail (D-M5b-14). The system maker is Quick Look's; tests use fakes. A request whose task is
/// cancelled should end soon with nil.
public protocol ThumbnailMaking {
    func thumbnail(for url: URL, side: Double, scale: Double) async -> CGImage?
}

/// `QLThumbnailGenerator`: the work happens off the main thread; a cancelled task cancels the request. Icon mode
/// gives Finder's decorated thumbnails (a page with its edge and shadow, the type's icon for plain text), so a box of
/// documents does not turn into a wall of white squares on the dark glass.
public struct SystemThumbnailMaker: ThumbnailMaking {
    public init() {}

    public func thumbnail(for url: URL, side: Double, scale: Double) async -> CGImage? {
        let request = Self.request(for: url, side: side, scale: scale)
        let generator = QLThumbnailGenerator.shared
        return await withTaskCancellationHandler {
            try? await generator.generateBestRepresentation(for: request).cgImage
        } onCancel: {
            generator.cancel(request)
        }
    }

    nonisolated static func request(for url: URL, side: Double, scale: Double) -> QLThumbnailGenerator.Request {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail)
        request.iconMode = true
        return request
    }
}

/// The two sizes the box asks for: the panel's cell and the tray's strip (19c §3.2, §3.4).
public enum ThumbnailSize: String, Sendable, CaseIterable {
    case cell, tray

    public var side: Double {
        switch self {
        case .cell: Double(BoxLook.Grid.thumb)
        case .tray: Double(BoxLook.Tray.thumb)
        }
    }
}

/// Where the box keeps its thumbnails (one image per item and size).
public protocol ThumbnailStoring: AnyObject {
    func object(forKey key: NSString) -> NSImage?
    func setObject(_ image: NSImage, forKey key: NSString)
}

/// An `NSCache` bounded by a count: the system may take images back under memory pressure, and the box then asks
/// Quick Look again when the cell is next on screen.
public final class SystemThumbnailStore: ThumbnailStoring {
    private let images = NSCache<NSString, NSImage>()

    public init(countLimit: Int = ThumbnailCache.countLimit) {
        images.countLimit = countLimit
    }

    public var countLimit: Int { images.countLimit }

    public func object(forKey key: NSString) -> NSImage? { images.object(forKey: key) }

    public func setObject(_ image: NSImage, forKey key: NSString) { images.setObject(image, forKey: key) }
}
