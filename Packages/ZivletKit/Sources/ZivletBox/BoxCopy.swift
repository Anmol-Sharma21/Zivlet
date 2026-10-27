import Foundation
import ZivletActions
import ZivletShelfCore

/// Every string the Drop Box shows (19c §5), in Zivlet's own words. Counts use the actions' plural rule; sizes are
/// decimal, as Finder shows them.
nonisolated enum BoxCopy {
    static let empty = "Drop files here"

    /// The card's title when no item of the selection (or the box) can take part.
    static func nothingUsable(_ press: BoxPress) -> String {
        switch press {
        case .share: "Nothing here can be shared."
        case .airDrop: "Nothing here can be sent."
        case .moveTo: "Nothing here can be moved."
        case .trash: "Nothing here can be moved to the Trash."
        default: "Nothing here can be copied."
        }
    }

    static let someNotAdded = "Some items weren't added."
    static let nothingAdded = "Nothing was added."
    static let alreadyInBox = "Already in the box"
    static let boxFull = "The box is full."
    static func alreadyIn(_ name: String) -> String { "\(name) is already in the box." }
    static func didNotFit(_ name: String) -> String {
        "\(name) didn't fit: a box holds \(ShelfLibrary.maxItemsPerBox.formatted()) items."
    }
    static func notFiles(_ count: Int) -> String {
        count == 1
            ? "1 item couldn't be added: only files and folders on this Mac can go in a box."
            : "\(count) items couldn't be added: only files and folders on this Mac can go in a box."
    }
    static let leftOut = "Some items were left out."
    static func lostTrack(_ name: String) -> String { "\(name) moved, but the box lost track of it." }
    static func changed(_ name: String) -> String { "\(name) is no longer the file that was added." }
    static let sharingFailed = "Sharing didn't finish."

    static let cleared = "Cleared"
    static let undo = "Undo"
    static let storageEmptied = "Box storage emptied"

    static func storage(_ bytes: Int64) -> String { "Box storage \(size(bytes))" }
    static let nothingTrashed = "Nothing was moved to the Trash."
    static let someStayed = "Some items stayed in the box."

    /// The busy overlay's verb while a bulk action runs (G-M5b-9).
    static func moving(_ count: Int) -> String { "Moving \(items(count))" }
    static func copying(_ count: Int) -> String { "Copying \(items(count))" }
    static func trashing(_ count: Int) -> String { "Moving \(items(count)) to the Trash" }

    /// The card of a Move to Trash stopped part-way: what is left in the box.
    static func stillHere(_ count: Int) -> String {
        "Stopped. \(items(count)) \(count == 1 ? "is" : "are") still here."
    }

    static func trashed(_ count: Int) -> String { "Moved \(count) to the Trash" }
    static func notTrashed(_ name: String) -> String { "\(name) couldn't be moved to the Trash." }
    /// The card line for a refused item, with the system's reason when it gave one.
    static func notTrashed(_ failure: TrashFailure) -> String {
        guard let refusal = failure.refusal else { return notTrashed(failure.name) }
        return "\(failure.name) couldn't be moved to the Trash: \(refusal.words)."
    }
    static func copyStayed(_ name: String) -> String { "\(name) stayed: its kept copy couldn't be moved to the Trash." }
    static func locateMessage(_ name: String) -> String { "Find “\(name)”." }

    static func items(_ count: Int) -> String { counted(count, "item") }

    static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    static func selection(_ selected: Int, of total: Int) -> String { "\(selected) of \(total)" }
    static func missing(_ count: Int) -> String { "\(count) missing" }
    static func add(_ count: Int) -> String { "Add \(count)" }
    static func added(_ count: Int) -> String { "Added \(count)" }
    static func inBox(_ count: Int) -> String { "\(count) in box" }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction.isNaN ? 0 : fraction, 0), 1) * 100).rounded()))%"
    }

    static func confirm(_ kind: ConfirmKind) -> String {
        switch kind {
        case .trash(let count): "Move \(count) to Trash?"
        case .clear: "Clear the box?"
        case .emptyStorage: "Empty box storage?"
        }
    }

    /// The tooltip and accessibility label of a button.
    static func title(_ press: BoxPress) -> String {
        switch press {
        case .share: "Share"
        case .airDrop: "AirDrop"
        case .copy: "Copy"
        case .moveTo: "Move to…"
        case .copyTo: "Copy to…"
        case .copyPaths: "Copy Paths"
        case .trash: "Move to Trash"
        case .remove: "Remove from Box"
        case .clear: "Clear Box"
        case .more: "More"
        case .grid: "Grid"
        case .list: "List"
        case .openPanel: "Open Drop Box"
        case .locate: "Locate…"
        case .quickLook: "Quick Look"
        case .removeMissing: "Remove Missing"
        case .emptyStorage: "Empty Box Storage"
        case .cancelBusy, .confirm(false): "Cancel"
        case .confirm(true): "Confirm"
        case .select, .clearSelection, .marquee, .draggedOut, .shown: ""
        }
    }
}
