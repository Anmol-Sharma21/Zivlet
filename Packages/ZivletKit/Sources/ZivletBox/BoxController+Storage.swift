import AppKit
import ZivletActions
import ZivletShelfCore
import os

/// Box storage and auto-clear (P2-141, OWN-APP-3, 17e §2.3): the overflow menu's storage line, Empty Box Storage,
/// and the auto-clear policy, run when items leave (a drag-out that landed, a finished Move), at launch and each time
/// the box is shown. No timers, so an idle box never wakes Zivlet.
extension BoxController {
    /// Bytes of every box's owned copies, as last counted (at launch and after every change).
    public var storageBytes: Int64 { ownedBytes }

    /// The owned items' sizes, measured when each copy was made: no walk of the storage folder on the main thread.
    func refreshStorage() {
        ownedBytes = library.boxes.flatMap(\.items).filter(\.isOwned).compactMap(\.byteCount).reduce(0, +)
    }

    /// Copies under the storage root that no item, and no Clear still in its undo window, points at go to the
    /// Trash. Run at a clean launch and by Empty Box Storage.
    func sweepStrays() {
        var keeping = library.ownedPaths
        for item in pendingClear?.shelf.items ?? [] {
            if case .owned(let relative) = item.ownership { keeping.insert(relative) }
        }
        let strays = ports.storage.strays(keeping: keeping)
        guard !strays.isEmpty else { return }
        Self.logger.notice("Drop Box: \(strays.count, privacy: .public) unreferenced copies to the Trash")
        for stray in strays {
            do {
                try ports.trash.trash(stray)
            } catch {
                Self.logger.error("Drop Box: an unreferenced copy could not be moved to the Trash")
            }
        }
    }

    /// The overflow menu's Empty Box Storage: asks first on the card's inline line.
    func requestEmptyStorage() {
        guard library.boxes.contains(where: { $0.items.contains(where: \.isOwned) }) else { return }
        requestConfirm(.emptyStorage)
    }

    /// Every box's owned items leave and their files go to the Trash; a copy the Trash refuses keeps its item.
    /// Settings › General asks before it calls this.
    public func emptyStorage() {
        var next = library
        var lines: [String] = []
        for box in library.boxes {
            let owned = box.items.filter(\.isOwned)
            guard !owned.isEmpty else { continue }
            let (kept, refused) = trashOwnedCopies(owned)
            lines += refused
            next = next.replacing(box.removing(Set(owned.map(\.id)).subtracting(kept)))
        }
        replace(next)
        sweepStrays()
        let result: ActionResult =
            lines.isEmpty
            ? .done(toast: BoxCopy.storageEmptied, undo: nil)
            : .failed(ActionCard(title: BoxCopy.someStayed, lines: lines))
        report(result)
    }

    /// Runs the auto-clear policy over every box; `left` holds the items whose drag-out or Move just finished.
    func clearAutomatically(left: Set<UUID>) {
        let policy = autoClear()
        guard policy != .off else { return }
        var next = library
        var lines: [String] = []
        for box in library.boxes {
            let ids = AutoClearPlan.items(in: box, policy: policy, now: ports.now(), left: left)
            guard !ids.isEmpty else { continue }
            let (kept, refused) = trashOwnedCopies(box.items.filter { ids.contains($0.id) })
            lines += refused
            next = next.replacing(box.removing(ids.subtracting(kept)))
        }
        if next != library { replace(next) }
        if !lines.isEmpty { report(.failed(ActionCard(title: BoxCopy.someStayed, lines: lines))) }
    }
}
