import AppKit

/// The two pasteboard calls Copy needs, so a test can record them instead of touching the person's clipboard.
public protocol SecretPasteboardTarget {
    @discardableResult
    func prepareForNewContents(with options: NSPasteboard.ContentsOptions) -> Int
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: SecretPasteboardTarget {}

/// Copy beside Suggest (P2-101, FR-96's [challenge] in 17b): the password goes on the general pasteboard for this Mac
/// only (not Universal Clipboard), marked concealed and transient (the nspasteboard.org markers) so clipboard managers
/// that honour them neither show nor keep it.
public struct SecretPasteboard {
    public static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    public static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let target: any SecretPasteboardTarget

    public init(target: any SecretPasteboardTarget = NSPasteboard.general) {
        self.target = target
    }

    /// Writes `text` with the markers; false when there is nothing to copy or the pasteboard refused it.
    public func copy(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.concealed)
        item.setData(Data(), forType: Self.transient)
        target.prepareForNewContents(with: .currentHostOnly)
        return target.writeObjects([item])
    }
}
