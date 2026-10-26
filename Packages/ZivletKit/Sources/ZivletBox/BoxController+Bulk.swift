import AppKit
import ZivletActions
import ZivletShelfCore

/// The bulk commands (P2-142, 17e §2.3 "Bulk actions"): each works on the selection, or on every item when nothing is
/// selected. Items that cannot be used now are left out and listed on the result card. Results go to `onResult`,
/// which the app forwards to the action toast at the notch or near the drop (D-M5a-3).
extension BoxController {
    /// The selection's usable items (or every one), in the box's order, with what cannot take part.
    func bulkTargets() -> BulkTargets {
        guard let shelf = current else { return BulkTargets(urls: [], ids: [], failures: []) }
        return BulkTargets.resolve(selection: selection.selected, in: shelf, statuses: statuses)
    }

    /// The system share picker at the Share button; no toast follows, the system reports nothing useful.
    func share() {
        guard let targets = usableTargets(.share) else { return }
        actions.sharePicker.show(targets.urls, relativeTo: BoxLook.Panel.shareAnchor, of: dropView, edge: .minY)
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
        guard let targets = usableTargets(.airDrop) else { return }
        running = Task { [actions] in
            report(await actions.send(targets.urls).listing(lines: targets.failures))
        }
    }

    /// Move to…: the folder chooser, one undo entry for the batch, then the moved items point at their new places.
    /// Items that were not moved stay as they were and are listed.
    func moveItems() {
        guard let targets = usableTargets(.moveTo), let box = current?.id else { return }
        running = Task { [actions] in
            let (result, moveReport) = await actions.move(targets.urls)
            let moved = moveReport.map { follow($0.moved, in: box, targets: targets) } ?? []
            report(result.listing(lines: targets.failures))
            clearAutomatically(left: moved)
        }
    }

    /// Copy to…: the folder chooser and one undo entry; the box keeps pointing at the originals.
    func copyItemsTo() {
        guard let targets = usableTargets(.copyTo) else { return }
        running = Task { [actions] in
            report(await actions.copy(to: targets.urls).listing(lines: targets.failures))
        }
    }

    /// Points the items that moved at their new paths (new bookmarks too) and saves; the ids that moved.
    @discardableResult
    func follow(_ moved: [MovedItem], in box: UUID, targets: BulkTargets) -> Set<UUID> {
        let ids = Dictionary(
            zip(targets.urls.map(\.standardizedFileURL.path), targets.ids), uniquingKeysWith: { first, _ in first })
        let moves = Dictionary(
            moved.compactMap { item in ids[item.source.standardizedFileURL.path].map { ($0, item.target.path) } },
            uniquingKeysWith: { first, _ in first })
        guard !moves.isEmpty, let shelf = library.boxes.first(where: { $0.id == box }) else { return [] }
        for (id, path) in moves { statuses[id] = .present(path: path) }
        replace(library.replacing(shelf.relocating(moves, using: ports.maker).0))
        return Set(moves.keys)
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
    func report(_ result: ActionResult) {
        onResult(result, panel.isVisible ? panel.frame : nil)
    }
}
