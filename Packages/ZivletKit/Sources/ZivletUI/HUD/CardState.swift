import AppKit
import Observation

/// What changes on a shown card after it appears: the undo reply, the details disclosure, the thumbnail.
@Observable
public final class CardState {
    public internal(set) var undoMessage: String?
    /// The last undo left files the Trash refused, so Undo stays available.
    public internal(set) var undoCanRetry = false
    public internal(set) var showsDetails = false
    public internal(set) var thumbnail: NSImage?

    public init() {}
}
