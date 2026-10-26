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

    static let cleared = "Cleared"
    static let storageEmptied = "Box storage emptied"

    static func storage(_ bytes: Int64) -> String { "Box storage \(size(bytes))" }
    static let nothingTrashed = "Nothing was moved to the Trash."
    static let someStayed = "Some items stayed in the box."

    static func trashed(_ count: Int) -> String { "Moved \(count) to the Trash" }
    static func notTrashed(_ name: String) -> String { "\(name) couldn't be moved to the Trash." }
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
        case .removeMissing: "Remove Missing"
        case .emptyStorage: "Empty Box Storage"
        case .cancelBusy, .confirm(false): "Cancel"
        case .confirm(true): "Confirm"
        case .select, .clearSelection, .marquee, .draggedOut: ""
        }
    }
}
