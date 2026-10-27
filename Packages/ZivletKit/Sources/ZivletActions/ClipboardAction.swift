import AppKit

/// The pasteboard calls the clipboard actions need, so a refusing pasteboard can be tested.
public protocol PasteboardWriting {
    /// Clears the pasteboard and writes `objects`; false when the pasteboard refused them.
    func replaceContents(with objects: [any NSPasteboardWriting]) -> Bool
    /// The same, kept on this Mac: not offered to Universal Clipboard (P2-104).
    func replaceContentsForThisMac(with objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: PasteboardWriting {
    public func replaceContents(with objects: [any NSPasteboardWriting]) -> Bool {
        clearContents()
        return writeObjects(objects)
    }

    public func replaceContentsForThisMac(with objects: [any NSPasteboardWriting]) -> Bool {
        prepareForNewContents(with: .currentHostOnly)
        return writeObjects(objects)
    }
}

/// Copy, Copy Path (P1-44, 03b §7 rows 3 and 5) and the text of Copy Text (P2-104).
public struct ClipboardAction {
    private let pasteboard: any PasteboardWriting

    public init(pasteboard: any PasteboardWriting = NSPasteboard.general) {
        self.pasteboard = pasteboard
    }

    /// The items themselves, as file URLs, so Finder's Paste copies them.
    public func copyItems(_ urls: [URL]) -> ActionOutcome {
        write(urls.map { $0 as NSURL }, toast: "Copied " + counted(urls.count, "item"))
    }

    /// One string: newline-separated paths, or shell-quoted and space-separated when ⌥ was held.
    public func copyPaths(_ urls: [URL], shellQuoted: Bool) -> ActionOutcome {
        let text = shellQuoted ? PathFormatter.shell(urls) : PathFormatter.lines(urls)
        return write([text as NSString], toast: "Copied " + counted(urls.count, "path"))
    }

    /// Recognised text as a plain string, for this Mac only (P2-104).
    public func copyText(_ text: String) -> ActionOutcome {
        pasteboard.replaceContentsForThisMac(with: [text as NSString])
            ? .done(toast: "Text copied") : .failed(.clipboardRefused)
    }

    private func write(_ objects: [any NSPasteboardWriting], toast: String) -> ActionOutcome {
        pasteboard.replaceContents(with: objects) ? .done(toast: toast) : .failed(.clipboardRefused)
    }
}
