import Foundation

/// Moves a file to the Trash. Owned copies are trashed, never unlinked, so the person can still get them back.
public protocol Trashing: Sendable {
    /// Where the item is now, inside the Trash, so Undo can put it back; nil when the system did not say.
    @discardableResult func trash(_ url: URL) throws(ShelfError) -> URL?
}

/// `FileManager.trashItem`.
public struct SystemTrash: Trashing {
    public init() {}

    @discardableResult public func trash(_ url: URL) throws(ShelfError) -> URL? {
        var placed: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &placed)
        } catch {
            throw .trashFailed
        }
        return placed as URL?
    }
}
