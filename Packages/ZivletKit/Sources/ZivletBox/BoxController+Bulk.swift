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
        let targets = bulkTargets()
        guard !targets.isEmpty else {
            return report(.failed(ActionCard(title: BoxCopy.nothingToShare, lines: targets.failures)))
        }
        actions.sharePicker.show(targets.urls, relativeTo: BoxLook.Panel.shareAnchor, of: dropView, edge: .minY)
    }

    /// Hands a result to the presenters, with the panel's frame (nil when it is off screen) as the anchor.
    func report(_ result: ActionResult) {
        onResult(result, panel.isVisible ? panel.frame : nil)
    }
}
