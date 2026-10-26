import Foundation

/// Moves a file to the Trash. Owned copies are trashed, never unlinked, so the person can still get them back.
public protocol Trashing: Sendable {
    func trash(_ url: URL) throws(ShelfError)
}

/// `FileManager.trashItem`.
public struct SystemTrash: Trashing {
    public init() {}

    public func trash(_ url: URL) throws(ShelfError) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            throw .trashFailed
        }
    }
}
