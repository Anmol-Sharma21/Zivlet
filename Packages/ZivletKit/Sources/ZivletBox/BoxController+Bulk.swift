import AppKit
import ZivletActions
import ZivletShelfCore
import os

/// The bulk commands (P2-142, 17e §2.3 "Bulk actions"): each works on the selection, or on every item when nothing is
/// selected. Items that cannot be used now are left out and listed on the result card. Results go to `onResult`,
/// which the app forwards to the action toast at the notch or near the drop (D-M5a-3).
extension BoxController {
    /// The selection's usable items (or every one), in the box's order, with what cannot take part. The bookmarks
    /// are the truth, not a status from an earlier show: each target is resolved again now (0.02 ms an item), and one
    /// whose identity no longer matches is left out, so Trash and Move never act on a file that took an old path.
    func bulkTargets() -> BulkTargets {
        guard let shelf = current else { return BulkTargets(urls: [], ids: [], failures: []) }
        let chosen =
            selection.selected.isEmpty ? shelf.items : shelf.items.filter { selection.selected.contains($0.id) }
        for item in chosen {
            statuses[item.id] = ItemStatus.from(ports.resolver.resolve(item.bookmark), isMounted: ports.isMounted)
        }
        return verified(BulkTargets.resolve(selection: selection.selected, in: shelf, statuses: statuses), in: shelf)
    }

    /// The targets without the items whose file is no longer the one that was added (its identity changed).
    private func verified(_ targets: BulkTargets, in shelf: Shelf) -> BulkTargets {
        let byID = Dictionary(shelf.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var (urls, ids, failures) = ([URL](), [UUID](), targets.failures)
        for (id, url) in zip(targets.ids, targets.urls) {
            if let item = byID[id], let identity = item.identity, let found = ports.maker.identity(of: url),
                found != identity
            {
                failures.append(BoxCopy.changed(item.displayName))
            } else {
                urls.append(url)
                ids.append(id)
            }
        }
        return BulkTargets(urls: urls, ids: ids, failures: failures)
    }

    /// The system share picker at the Share button. The system reports nothing useful about a share that works, so
    /// no toast follows; items left out get a card, and a service that fails says so.
    func share() {
        guard let targets = usableTargets(.share) else { return }
        actions.sharePicker.show(targets.urls, relativeTo: BoxLook.Panel.shareAnchor, of: dropView, edge: .minY)
        if !targets.failures.isEmpty { report(.failed(ActionCard(title: BoxCopy.leftOut, lines: targets.failures))) }
    }

    func copyItems() {
        guard let targets = usableTargets(.copy) else { return }
        report(actions.copy(targets.urls).listing(lines: targets.failures))
    }

    /// Newline-separated paths; shell-quoted when asked (⌥ on the menu item, never the ⌘⌥C key itself).
    func copyPaths(shellQuoted: Bool) {
        guard let targets = usableTargets(.copyPaths) else { return }
        report(actions.copyPaths(targets.urls, shellQuoted: shellQuoted).listing(lines: targets.failures))
    }

    func airDrop() {
        guard running == nil, let targets = usableTargets(.airDrop) else { return }
        runBulk { [self, actions] in
            report(await actions.send(targets.urls).listing(lines: targets.failures))
        }
    }

    /// Move to…: the folder chooser, one undo entry for the batch, then the moved items point at their new places.
    /// Items that were not moved stay as they were and are listed. The busy overlay shows while it runs; Cancel or
    /// Esc stops it between items, and what moved keeps its Undo.
    func moveItems() {
        guard running == nil, let targets = usableTargets(.moveTo), let box = current?.id else { return }
        runBusy(BoxCopy.moving) { [self, actions] progress in
            let (result, moveReport) = await actions.move(targets.urls, progress: progress)
            let (moved, lost) = moveReport.map { follow($0.moved, in: box, targets: targets) } ?? ([], [])
            report(result.listing(lines: targets.failures + lost))
            clearAutomatically(left: moved)
        }
    }

    /// Copy to…: the folder chooser and one undo entry; the box keeps pointing at the originals. Busy and Cancel as
    /// for Move to….
    func copyItemsTo() {
        guard running == nil, let targets = usableTargets(.copyTo) else { return }
        runBusy(BoxCopy.copying) { [self, actions] progress in
            report(await actions.copy(to: targets.urls, progress: progress).listing(lines: targets.failures))
        }
    }

    /// One bulk action at a time (AirDrop, Move to…, Copy to…, Locate…): a press while one runs, its folder chooser
    /// or AirDrop sheet still open, does nothing, and the handle is never lost.
    func runBulk(_ work: @escaping () async -> Void) {
        guard running == nil else { return }
        running = Task { [weak self] in
            await work()
            self?.running = nil
        }
    }

    /// Points the items that moved at their new paths (new bookmarks and identities too) and saves; the ids that
    /// moved and are still followed, and a line for each one whose new bookmark could not be made.
    @discardableResult
    func follow(_ moved: [MovedItem], in box: UUID, targets: BulkTargets) -> (moved: Set<UUID>, lost: [String]) {
        let ids = Dictionary(
            zip(targets.urls.map(\.standardizedFileURL.path), targets.ids), uniquingKeysWith: { first, _ in first })
        let moves = Dictionary(
            moved.compactMap { item in ids[item.source.standardizedFileURL.path].map { ($0, item.target.path) } },
            uniquingKeysWith: { first, _ in first })
        guard !moves.isEmpty, let shelf = library.boxes.first(where: { $0.id == box }) else { return ([], []) }
        let (next, failed) = shelf.relocating(moves, using: ports.maker, storage: ports.storage)
        for (id, path) in moves where !failed.contains(id) { statuses[id] = .present(path: path) }
        replace(library.replacing(next))
        if !failed.isEmpty { Self.logger.error("Drop Box: \(failed.count, privacy: .public) moved items not followed") }
        let lost = shelf.items.filter { failed.contains($0.id) }.map { BoxCopy.lostTrack($0.displayName) }
        return (Set(moves.keys).subtracting(failed), lost)
    }

    /// The targets when any item can take part; otherwise the card that says nothing can, and nil. An empty box has
    /// nothing to act on and says nothing (its bar is not even drawn).
    func usableTargets(_ press: BoxPress) -> BulkTargets? {
        guard current?.items.isEmpty == false else { return nil }
        let targets = bulkTargets()
        guard targets.isEmpty else { return targets }
        report(.failed(ActionCard(title: BoxCopy.nothingUsable(press), lines: targets.failures)))
        return nil
    }

    /// Hands a result to the presenters, with the panel's frame (nil when it is off screen) as the anchor.
    public func report(_ result: ActionResult) {
        onResult(result, panel.isVisible ? panel.frame : nil)
    }
}
