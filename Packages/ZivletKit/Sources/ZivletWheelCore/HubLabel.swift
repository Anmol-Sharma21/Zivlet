import Foundation
import ZivletCore

/// One dragged item as the hub label sees it. `byteCount` is nil for folders and unreadable items.
public struct HubItem: Sendable, Equatable {
    public let name: String
    public let format: FormatID?
    public let kind: SelectionItemKind
    public let byteCount: Int64?

    public init(name: String, format: FormatID?, kind: SelectionItemKind, byteCount: Int64?) {
        self.name = name
        self.format = format
        self.kind = kind
        self.byteCount = byteCount
    }
}

/// Idle hub text (03a §2.6): one file → name + size; n files of one type → "<n> <TYPE> FILES" + total; other files →
/// "MIXED" + total; folders → "FOLDER" / "<n> FOLDERS"; files and folders → "<n> ITEMS".
public enum HubLabel {
    public static func text(for items: [HubItem], registry: FormatRegistry = .standard) -> String {
        guard let first = items.first else { return "" }
        let folders = items.count { $0.kind == .folder }
        if folders == items.count { return folders == 1 ? "FOLDER" : "\(folders) FOLDERS" }
        if folders > 0 { return "\(items.count) ITEMS" }
        let headline: String
        if items.count == 1 {
            headline = first.name
        } else if let format = first.format, items.allSatisfy({ $0.format == format }) {
            headline = "\(items.count) \(registry.format(format).wheelLabel) FILES"
        } else {
            headline = "MIXED"
        }
        return [headline, totalSize(items)].compactMap { $0 }.joined(separator: "\n")
    }

    /// Compact style (7 pt semibold) for more than one source item, else 10 pt medium (03a §2.2).
    public static func isCompact(for items: [HubItem]) -> Bool { items.count > 1 }

    /// Nil unless every size is known, so the hub never shows a partial total.
    private static func totalSize(_ items: [HubItem]) -> String? {
        let sizes = items.compactMap(\.byteCount)
        guard sizes.count == items.count else { return nil }
        return ByteSize.text(sizes.reduce(0, +))
    }
}

/// Decimal (1000-based) sizes like Finder: one decimal below 10, whole numbers above, POSIX digits.
public enum ByteSize {
    static let units = ["KB", "MB", "GB", "TB"]

    public static func text(_ bytes: Int64) -> String {
        switch bytes {
        case ...0: "Zero bytes"
        case 1: "1 byte"
        case 2..<1_000: "\(bytes) bytes"
        default: scaled(Double(bytes) / 1_000, unit: 0)
        }
    }

    private static func scaled(_ value: Double, unit: Int) -> String {
        let tenths = (value * 10).rounded() / 10
        if tenths < 10 { return String(format: "%.1f %@", tenths, units[unit]) }
        let whole = value.rounded()
        if whole >= 1_000, unit < units.count - 1 { return scaled(value / 1_000, unit: unit + 1) }
        return "\(Int64(whole)) \(units[unit])"
    }
}
