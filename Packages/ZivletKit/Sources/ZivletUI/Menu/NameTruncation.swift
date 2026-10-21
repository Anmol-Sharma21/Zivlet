import Foundation

/// Long file names in menus (03b §8.3): the middle gives way, the start and the extension stay.
public enum NameTruncation {
    static let maxExtensionLength = 8

    public static func middle(_ name: String, limit: Int) -> String {
        guard name.count > limit, limit > 2 else { return name }
        let ext = (name as NSString).pathExtension
        let keepsExtension = !ext.isEmpty && ext.count < maxExtensionLength
        let suffix = keepsExtension ? "." + ext : ""
        let stem = keepsExtension ? String(name.dropLast(suffix.count)) : name
        let budget = limit - 1 - suffix.count
        guard budget > 1 else { return String(name.prefix(limit - 1)) + "…" }
        let headCount = (budget + 1) / 2
        let head = stem.prefix(headCount).trimmingTrailingWhitespace
        let tail = stem.suffix(budget - headCount).trimmingLeadingWhitespace
        return head + "…" + tail + suffix
    }
}

extension Substring {
    fileprivate var trimmingTrailingWhitespace: String {
        String(self[..<(lastIndex { !$0.isWhitespace }.map(index(after:)) ?? startIndex)])
    }

    fileprivate var trimmingLeadingWhitespace: String {
        String(self[(firstIndex { !$0.isWhitespace } ?? endIndex)...])
    }
}
