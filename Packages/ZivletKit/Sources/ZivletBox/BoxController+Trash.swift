import Foundation
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletShelfCore

/// Move to Trash (P2-142, G-M5b-8, G-M5b-9): the files go to the Trash off the main thread, with the busy overlay and
/// Cancel when there is more than one; the box then drops the items that went, judged against the box as it is now
/// (an item removed meanwhile stays removed), and the batch can be undone.
extension BoxController {
    /// How many Moves to Trash the box remembers for Undo.
    static let trashUndoMemory = 20

    /// The files themselves go to the Trash and leave the box; what the Trash refuses stays and is listed.
    func trash(_ targets: BulkTargets) {
        guard let box = current?.id else { return }
        let trasher = BoxTrasher(trash: ports.trash)
        let count = targets.ids.count
        runBusy(BoxCopy.trashing) { [self] progress in
            if count > 1 { progress.started(count) }
            let outcome = await trasher.run(ids: targets.ids, urls: targets.urls, progress: progress.advanced)
            await finishTrash(outcome, targets: targets, box: box)
        }
    }

    /// The report applied to the box, one undo batch recorded, and the toast or card.
    private func finishTrash(_ outcome: TrashReport, targets: BulkTargets, box: UUID) async {
        let lines = targets.failures + outcome.failed.map(BoxCopy.notTrashed)
        guard !outcome.trashed.isEmpty else {
            guard !lines.isEmpty else { return report(.cancelled) }
            return report(.failed(ActionCard(title: BoxCopy.nothingTrashed, lines: lines)))
        }
        let batch = await recordTrashUndo(outcome.trashed)
        removeTrashed(outcome.trashed, batch: batch, box: box)
        let toast = BoxCopy.trashed(outcome.trashed.count)
        guard !outcome.cancelled.isEmpty else {
            return report(ActionResult.done(toast: toast, undo: batch).listing(lines: lines))
        }
        let card = ActionCard(title: BoxCopy.stillHere(outcome.cancelled.count + outcome.failed.count), lines: lines)
        report(.partial(toast: toast, card: card, undo: batch))
    }

    /// One undo batch for the items whose place in the Trash is known; nil when there is none.
    private func recordTrashUndo(_ trashed: [TrashedItem]) async -> BatchID? {
        let moves = trashed.compactMap { item in
            item.inTrash.flatMap { place in
                item.stamp.map { UndoMove(original: item.original, moved: place, stamp: $0) }
            }
        }
        guard !moves.isEmpty else { return nil }
        let batch = BatchID()
        await ports.recordUndo(batch, moves)
        return batch
    }

    /// Drops the trashed items from the box they were in, if it is still there, and remembers them for Undo.
    private func removeTrashed(_ trashed: [TrashedItem], batch: BatchID?, box: UUID) {
        guard let shelf = library.boxes.first(where: { $0.id == box }) else { return }
        let originals = Dictionary(trashed.map { ($0.id, $0.original) }, uniquingKeysWith: { first, _ in first })
        let entries = shelf.items.compactMap { item in
            originals[item.id].map { TrashBatch.Entry(item: item, original: $0) }
        }
        if let batch, !entries.isEmpty {
            let kept = trashBatches.suffix(Self.trashUndoMemory - 1)
            trashBatches = kept + [TrashBatch(batch: batch, box: box, entries: entries, order: shelf.items.map(\.id))]
        }
        replace(library.replacing(shelf.removing(Set(originals.keys))))
    }

    /// Undo of a Move to Trash put files back (`restored`, their old places): their items return to the box they came
    /// from, at their old places. Items whose file stayed in the Trash stay out, and Undo can be tried again for
    /// them. Any other batch is ignored.
    public func trashUndone(_ batch: BatchID, restored: [URL]) {
        guard let pending = trashBatches.first(where: { $0.batch == batch }) else { return }
        let back = Set(restored.map(\.standardizedFileURL.path))
        let (returning, waiting) = pending.entries.split { back.contains($0.original.standardizedFileURL.path) }
        trashBatches = trashBatches.compactMap { other in
            guard other.batch == batch else { return other }
            return waiting.isEmpty
                ? nil : TrashBatch(batch: batch, box: other.box, entries: waiting, order: other.order)
        }
        guard !returning.isEmpty, let shelf = library.boxes.first(where: { $0.id == pending.box }) else { return }
        for entry in returning { statuses[entry.item.id] = .present(path: entry.original.standardizedFileURL.path) }
        let grown = shelf.adding(returning.map(\.item), cap: ShelfLibrary.maxItemsPerBox).0
        let present = Set(grown.items.map(\.id))
        replace(library.replacing(grown.reordering(pending.order.filter(present.contains))))
    }
}

extension Array {
    /// The elements that match, then the rest, each in order.
    fileprivate func split(_ matches: (Element) -> Bool) -> ([Element], [Element]) {
        (filter(matches), filter { !matches($0) })
    }
}
