import AppKit
import ZivletShelfCore
import os

/// Adding to the box (P2-141): the BOX slice, a drop on the panel and a drop at the notch. The destination box is
/// chosen before the intake writes anything, so owned copies land in the folder of the box that keeps them; whatever
/// the library then does not take (duplicates, over the cap, too many boxes) goes to the Trash, so storage never
/// holds a copy no item points at.
extension BoxController {
    /// Adds files to the current box, or to a new one (⌥ on BOX, or the setting).
    public func add(_ urls: [URL], newBox: Bool) async -> AddOutcome {
        let local = urls.filter(\.isFileURL)
        guard !local.isEmpty else { return AddOutcome(added: 0, failure: IntakeResult.nothingUsable) }
        let box = destination(newBox: newBox)
        let result = await intake.references(local).noting(notFiles: urls.count - local.count)
        return adding(result, into: box, newBox: newBox).outcome
    }

    /// A drop on the panel, inside `performDragOperation`.
    public func receiveDrop(_ pasteboard: NSPasteboard) async -> AddOutcome {
        let outcome = await intakeDrop(pasteboard).outcome
        apply(.dropped)
        return outcome
    }

    /// The panel's and the tray's drop: always the current box (OWN-APP-1), the box the person is looking at.
    func intakeDrop(_ pasteboard: NSPasteboard) async -> TrayAdded {
        let box = destination(newBox: false)
        let result = await intake.receive(from: pasteboard, box: box)
        return adding(result, into: box, newBox: false)
    }

    /// The id of the box a drop lands in: the current box, or the id a new box will take.
    func destination(newBox: Bool) -> UUID {
        library.destinationID(newBox ? .newBox : .current) ?? UUID()
    }

    /// Adds the intake's items to `box` and says which ones went in, so a tray drop can be undone exactly. The added
    /// items were just read from real files, so they count as present until the next resolution.
    func adding(_ result: IntakeResult, into box: UUID, newBox: Bool) -> TrayAdded {
        var added: Set<UUID> = []
        defer { discard(result, keeping: added, box: box) }
        guard !result.items.isEmpty else {
            return TrayAdded(
                outcome: AddOutcome(added: 0, rejected: result.rejected, failure: result.rejected.first), ids: [])
        }
        do {
            let (next, report) = try library.adding(
                result.items, to: newBox ? .newBox : .current, now: ports.now(), newID: box)
            added = Set(report.added)
            for item in result.items where added.contains(item.id) {
                statuses[item.id] = .present(path: item.lastKnownPath)
            }
            replace(next)
            let outcome = AddOutcome(
                added: report.added.count, duplicates: report.duplicates, overCap: report.overCap,
                rejected: result.rejected)
            return TrayAdded(outcome: outcome, ids: report.added)
        } catch {
            return TrayAdded(
                outcome: AddOutcome(added: 0, rejected: result.rejected, failure: error.userMessage), ids: [])
        }
    }

    /// Owned copies the library did not take, and strays the intake wrote, go to the Trash; an empty folder left for
    /// a box that was never made goes too.
    private func discard(_ result: IntakeResult, keeping added: Set<UUID>, box: UUID) {
        let unused = result.items.filter { $0.isOwned && !added.contains($0.id) }
        _ = trashOwnedCopies(unused)
        for stray in result.strays {
            do {
                try ports.trash.trash(stray)
            } catch {
                Self.logger.error("Drop Box: a copy it did not keep stayed in its storage")
            }
        }
        if !library.boxes.contains(where: { $0.id == box }) { ports.storage.removeFolderIfEmpty(for: box) }
    }
}
