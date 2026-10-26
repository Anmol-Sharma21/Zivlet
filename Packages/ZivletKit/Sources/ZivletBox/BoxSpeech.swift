import Foundation
import ZivletActions
import ZivletShelfCore

/// What VoiceOver says for the box (19c §5, §6): items with their size and folder, or why they cannot be used; the
/// header with the unit spelled out. Pure.
nonisolated public enum BoxSpeech {
    public static func item(_ name: String, bytes: Int64?, status: ItemStatus?) -> String {
        switch status {
        case .missing: return "\(name), missing"
        case .inTrash: return "\(name), in the Trash"
        case .volumeOffline(let volume): return "\(name), on \(volume), not connected"
        case .present(let path):
            let folder = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            return ([name] + (bytes.map { [BoxCopy.size($0)] } ?? []) + ["in \(folder)"]).joined(separator: ", ")
        case nil:
            return ([name] + (bytes.map { [BoxCopy.size($0)] } ?? [])).joined(separator: ", ")
        }
    }

    public static func header(count: Int, bytes: Int64) -> String {
        count == 0 ? "Drop Box, empty. \(BoxCopy.empty)" : "Drop Box, \(counted(count, "item")), \(spoken(bytes))"
    }

    public static func selection(_ selected: Int, of total: Int) -> String { "\(selected) of \(total) items selected" }
    public static func missing(_ count: Int) -> String { "\(counted(count, "item")) missing" }
    public static func dropTarget(_ count: Int) -> String { "Add \(counted(count, "item")) to the Drop Box" }
    public static func added(_ count: Int) -> String { "Added \(counted(count, "item"))" }

    /// "84 megabytes": decimal units, one decimal place below ten, the unit spelled out.
    static func spoken(_ bytes: Int64) -> String {
        let units = ["kilobyte", "megabyte", "gigabyte", "terabyte"]
        guard bytes >= 1_000 else { return counted(Int(bytes), "byte") }
        var value = Double(bytes)
        var unit = 0
        value /= 1_000
        while value >= 1_000, unit < units.count - 1 {
            value /= 1_000
            unit += 1
        }
        let rounded = value < 10 ? (value * 10).rounded() / 10 : value.rounded()
        let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return "\(text) \(units[unit])\(rounded == 1 ? "" : "s")"
    }
}
