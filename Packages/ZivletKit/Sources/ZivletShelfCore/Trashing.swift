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
            throw TrashRefusal(error).map(ShelfError.trashRefused) ?? .trashFailed
        }
        return placed as URL?
    }
}

/// Why the system refused to trash an item, when its error says: the few words a card line and the log use.
public enum TrashRefusal: String, Sendable, Equatable {
    case noPermission, readOnlyVolume, missing

    public init?(_ error: any Error) {
        guard let error = error as? CocoaError else { return nil }
        switch error.code {
        case .fileWriteNoPermission, .fileReadNoPermission: self = .noPermission
        case .fileWriteVolumeReadOnly: self = .readOnlyVolume
        case .fileNoSuchFile, .fileReadNoSuchFile: self = .missing
        default: return nil
        }
    }

    public var words: String {
        switch self {
        case .noPermission: "no permission"
        case .readOnlyVolume: "the disk is read-only"
        case .missing: "it's no longer there"
        }
    }
}
