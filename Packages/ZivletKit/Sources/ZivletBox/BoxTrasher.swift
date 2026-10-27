import Foundation
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletShelfCore
import os

/// One box item whose file went to the Trash: where it was, where it is now (nil when the system did not say) and
/// its stamp there, so Undo can check it is unchanged.
nonisolated struct TrashedItem: Sendable, Equatable {
    let id: UUID
    let original: URL
    let inTrash: URL?
    let stamp: FileStamp?
}

/// An item the Trash refused: its name, and why when the system said.
nonisolated struct TrashFailure: Sendable, Equatable {
    let name: String
    let refusal: TrashRefusal?
}

/// What a Move to Trash did: the items trashed, the ones the Trash refused, and the ids not tried because the run
/// was cancelled.
nonisolated struct TrashReport: Sendable, Equatable {
    let trashed: [TrashedItem]
    let failed: [TrashFailure]
    let cancelled: [UUID]
}

/// Moves the box's items to the Trash off the main thread (G-M5b-8), one at a time, checking for cancellation before
/// each (G-M5b-9): an item that started finishes, the rest stay where they are.
nonisolated struct BoxTrasher: Sendable {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "box")
    let trash: any Trashing

    @concurrent func run(ids: [UUID], urls: [URL], progress: MoveExecutor.Progress) async -> TrashReport {
        let pairs = Array(zip(ids, urls))
        var trashed: [TrashedItem] = []
        var failed: [TrashFailure] = []
        for (index, (id, url)) in pairs.enumerated() {
            guard !Task.isCancelled else {
                return TrashReport(trashed: trashed, failed: failed, cancelled: pairs[index...].map(\.0))
            }
            do {
                let place = try trash.trash(url)
                trashed.append(TrashedItem(id: id, original: url, inTrash: place, stamp: place.flatMap(FileStamp.read)))
            } catch {
                let refusal: TrashRefusal? = if case .trashRefused(let why) = error { why } else { nil }
                Self.logger.error("Not moved to the Trash: \(refusal?.rawValue ?? "unknown", privacy: .public)")
                failed.append(TrashFailure(name: url.lastPathComponent, refusal: refusal))
            }
            progress(index + 1, pairs.count)
        }
        return TrashReport(trashed: trashed, failed: failed, cancelled: [])
    }
}

/// A Move to Trash Undo can still reverse: the box it came from, its items and where each was, and the box's order
/// at the time, so the items return to their places.
struct TrashBatch {
    struct Entry {
        let item: ShelfItem
        let original: URL
    }

    let batch: BatchID
    let box: UUID
    let entries: [Entry]
    let order: [UUID]
}
