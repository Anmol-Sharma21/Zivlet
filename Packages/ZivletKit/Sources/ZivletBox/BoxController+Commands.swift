import AppKit
import ZivletActions
import ZivletCore
import ZivletShelfCore

/// A Clear that can still be undone: the box as it was, until its 10 s window ends.
struct PendingClear {
    let batch: BatchID
    let shelf: Shelf
}

/// Remove, Move to Trash, Clear, Locate… and Remove missing (P2-142, 17e §2.3). Confirmations are the inline line of
/// 19c D-BL9, never an alert (D-M5b-12). Owned copies always go to the Trash, never `unlink`.
extension BoxController {
    /// Clear offers Undo for this long, then its owned copies go to the Trash (D-M5b-21).
    static let clearUndoWindow = Duration.seconds(10)

    /// ⌫: the selected references go and their owned copies go to the Trash. Nothing selected asks to clear the box.
    func removeItems() {
        guard let shelf = current else { return }
        guard !selection.selected.isEmpty else { return requestConfirm(.clear) }
        remove(shelf.items.filter { selection.selected.contains($0.id) }, from: shelf)
    }

    /// Takes `chosen` out of `shelf`; owned copies go to the Trash, and those that cannot stay with a card.
    func remove(_ chosen: [ShelfItem], from shelf: Shelf) {
        let (kept, lines) = trashOwnedCopies(chosen)
        replace(library.replacing(shelf.removing(Set(chosen.map(\.id)).subtracting(kept))))
        if !lines.isEmpty { report(.failed(ActionCard(title: BoxCopy.someStayed, lines: lines))) }
    }

    /// ⌘⌫: one item goes to the Trash at once; more than one asks first.
    func trashItems() {
        guard let targets = usableTargets(.trash) else { return }
        guard targets.ids.count > 1 else { return trash(targets) }
        pendingTrash = targets
        requestConfirm(.trash(count: targets.ids.count))
    }

    func requestClear() {
        guard current?.items.isEmpty == false else { return }
        requestConfirm(.clear)
    }

    /// The person answered yes on the inline line.
    func confirmed(_ kind: ConfirmKind) {
        switch kind {
        case .trash:
            guard let targets = pendingTrash else { return }
            pendingTrash = nil
            trash(targets)
        case .clear: clearBox()
        case .emptyStorage: emptyStorage()
        }
    }

    /// The question lives on the expanded card, so a smaller panel opens first.
    func requestConfirm(_ kind: ConfirmKind) {
        if presentation.base != .expanded { showPanel() }
        apply(.confirmRequested(kind))
    }

    /// Every reference goes now; the owned copies wait out the undo window before they go to the Trash.
    func clearBox() {
        guard let shelf = current, !shelf.items.isEmpty else { return }
        if let earlier = pendingClear { finishClear(earlier.batch) }
        let batch = BatchID()
        pendingClear = PendingClear(batch: batch, shelf: shelf)
        replace(library.replacing(shelf.removing(Set(shelf.items.map(\.id)))))
        report(.done(toast: BoxCopy.cleared, undo: batch, linger: Self.clearUndoWindow))
        clearing = Task { [ports] in
            await ports.sleep(Self.clearUndoWindow)
            guard !Task.isCancelled else { return }
            finishClear(batch)
        }
    }

    /// Undo on the Clear toast, within its window: the items come back in front of anything added since. False when
    /// the batch is not a pending Clear (the window ended, or it is another kind of undo).
    public func undoClear(_ batch: BatchID) -> Bool {
        guard let pending = pendingClear, pending.batch == batch,
            let now = library.boxes.first(where: { $0.id == pending.shelf.id })
        else { return false }
        clearing?.cancel()
        pendingClear = nil
        let restored = now.adding(pending.shelf.items, cap: ShelfLibrary.maxItemsPerBox).0
        replace(library.replacing(restored.reordering(pending.shelf.items.map(\.id))))
        return true
    }

    /// The window ended (or Zivlet quits, or another Clear starts): the cleared owned copies go to the Trash. A copy
    /// the Trash refuses comes back into its box with a line, so it can be tried again and is never left unreachable.
    func finishClear(_ batch: BatchID) {
        guard let pending = pendingClear, pending.batch == batch else { return }
        pendingClear = nil
        let (kept, lines) = trashOwnedCopies(pending.shelf.items)
        guard !lines.isEmpty else { return }
        if let box = library.boxes.first(where: { $0.id == pending.shelf.id }) {
            let back = pending.shelf.items.filter { kept.contains($0.id) }
            replace(library.replacing(box.adding(back, cap: ShelfLibrary.maxItemsPerBox).0))
        }
        report(.failed(ActionCard(title: BoxCopy.someStayed, lines: lines)))
    }

    /// Locate… for the one selected item that is missing: the open panel, then a new bookmark at the chosen place.
    func locate() {
        guard let shelf = current, selection.selected.count == 1, let id = selection.selected.first,
            let item = shelf.items.first(where: { $0.id == id }), statuses[id]?.isAvailable == false
        else { return }
        let folder = URL(filePath: item.lastKnownPath).deletingLastPathComponent()
        runBulk { [self, ports] in
            guard let found = await ports.locator.locate(item.displayName, lastSeenIn: folder), found.isFileURL,
                let box = library.boxes.first(where: { $0.id == shelf.id })
            else { return }
            let path = found.standardizedFileURL.path
            let (next, failed) = box.relocating([id: path], using: ports.maker, storage: ports.storage)
            guard failed.isEmpty else {
                return report(.failed(ActionCard(title: ShelfError.bookmarkFailed.userMessage)))
            }
            statuses[id] = .present(path: path)
            replace(library.replacing(next))
        }
    }

    /// Missing and trashed items leave; items on a volume that is not connected stay, the drive may come back.
    func removeMissing() {
        guard let shelf = current else { return }
        let gone = shelf.items.filter { item in
            switch statuses[item.id] {
            case .missing, .inTrash: true
            case .present, .volumeOffline, nil: false
            }
        }
        replace(library.replacing(shelf.removing(Set(gone.map(\.id)))))
    }

    /// Trashes the owned copies among `items`; the ids whose copy the Trash refused, with a line each. A copy that
    /// is gone counts as done, and so does a path that now holds something else: the box only trashes the file the
    /// item itself points at, never a symbolic link or whatever later took the copy's name.
    func trashOwnedCopies(_ items: [ShelfItem]) -> (kept: Set<UUID>, lines: [String]) {
        var kept: Set<UUID> = []
        var lines: [String] = []
        for item in items {
            guard case .owned(let relative) = item.ownership else { continue }
            guard let url = try? ports.storage.url(forRelativePath: relative) else {
                kept.insert(item.id)
                lines.append(BoxCopy.copyStayed(item.displayName))
                continue
            }
            guard isOwnCopy(item, at: url) else { continue }
            do {
                try ports.trash.trash(url)
            } catch {
                kept.insert(item.id)
                lines.append(BoxCopy.copyStayed(item.displayName))
            }
        }
        return (kept, lines)
    }

    /// The file at `url` is there, is not a symbolic link, and is the item's own: the item's path (and its status,
    /// when resolved) name it, and its identity matches when both are known.
    func isOwnCopy(_ item: ShelfItem, at url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true,
            URL(filePath: item.lastKnownPath).standardizedFileURL.path == path
        else { return false }
        if case .present(let now) = statuses[item.id], URL(filePath: now).standardizedFileURL.path != path {
            return false
        }
        if let identity = item.identity, let found = ports.maker.identity(of: url), found != identity { return false }
        return true
    }
}
