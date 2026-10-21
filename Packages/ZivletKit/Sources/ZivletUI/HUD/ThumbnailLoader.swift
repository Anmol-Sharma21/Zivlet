import AppKit
import QuickLookThumbnailing

/// The card's thumbnail (P1-41): Quick Look's, 64 pt, made off the main thread; nil when Quick Look has none.
public enum ThumbnailLoader {
    public static let side: CGFloat = 64

    public static func thumbnail(for url: URL, scale: CGFloat = 2) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail)
        do {
            return try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        } catch {
            return nil
        }
    }

    /// Finder's icon for the file, until the thumbnail arrives.
    public static func placeholder(for url: URL) -> NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}
