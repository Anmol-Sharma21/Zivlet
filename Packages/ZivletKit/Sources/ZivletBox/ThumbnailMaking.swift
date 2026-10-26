import CoreGraphics
import Foundation
import QuickLookThumbnailing

/// Makes one thumbnail (D-M5b-14). The system maker is Quick Look's; tests use fakes. A request whose task is
/// cancelled should end soon with nil.
public protocol ThumbnailMaking {
    func thumbnail(for url: URL, side: Double, scale: Double) async -> CGImage?
}

/// `QLThumbnailGenerator`: the work happens off the main thread; a cancelled task cancels the request.
public struct SystemThumbnailMaker: ThumbnailMaking {
    public init() {}

    public func thumbnail(for url: URL, side: Double, scale: Double) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail)
        let generator = QLThumbnailGenerator.shared
        return await withTaskCancellationHandler {
            try? await generator.generateBestRepresentation(for: request).cgImage
        } onCancel: {
            generator.cancel(request)
        }
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
