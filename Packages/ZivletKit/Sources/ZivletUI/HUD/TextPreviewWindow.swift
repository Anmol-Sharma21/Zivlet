import AppKit

/// The Show All window's content: its title and the whole recognised text (P2-104).
public struct TextPreviewModel: Sendable, Equatable {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    /// "Text from photo.png", or "Text from 3 files".
    public static func title(names: [String]) -> String {
        names.count == 1 ? "Text from \(names[0])" : "Text from \(names.count) files"
    }
}

/// Show All (P2-104, plan 18d D11): a non-activating panel with a read-only, selectable text view on Liquid Glass, or
/// on the solid window background under Reduce Transparency. Escape and ⌘W close it. It keeps the text only while it
/// is open: closing it empties the view.
public final class TextPreviewWindow: NSPanel {
    static let size = CGSize(width: 520, height: 420)
    static let inset = CGSize(width: 16, height: 14)

    let textView: NSTextView
    private let scroll: NSScrollView

    public init() {
        scroll = NSScrollView(frame: NSRect(origin: .zero, size: Self.size))
        textView = NSTextView(frame: NSRect(origin: .zero, size: Self.size))
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        level = .floating
        titlebarAppearsTransparent = true
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        minSize = CGSize(width: 320, height: 200)
        configureText()
        applyBackground(reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    override public var canBecomeKey: Bool { true }

    /// Glass unless Reduce Transparency asks for a solid surface.
    static func usesGlass(reduceTransparency: Bool) -> Bool { !reduceTransparency }

    public func load(_ model: TextPreviewModel) {
        title = model.title
        textView.string = model.text
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }

    /// Loads `model` and shows the panel centred on the screen with the pointer, as the key window but without
    /// activating Zivlet: the person's own app stays frontmost.
    public func show(_ model: TextPreviewModel) {
        load(model)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameOrigin(CGPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2))
        }
        makeKeyAndOrderFront(nil)
    }

    override public func close() {
        super.close()
        textView.string = ""
    }

    override public func cancelOperation(_ sender: Any?) { close() }

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func configureText() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.textContainerInset = Self.inset
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Recognised text")
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]
    }

    private func applyBackground(reduceTransparency: Bool) {
        guard Self.usesGlass(reduceTransparency: reduceTransparency) else {
            scroll.drawsBackground = true
            scroll.backgroundColor = .windowBackgroundColor
            contentView = scroll
            return
        }
        isOpaque = false
        backgroundColor = .clear
        scroll.drawsBackground = false
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: Self.size))
        glass.cornerRadius = HUDInk.cornerRadius
        // The HUD's scrim, as a tint: the text holds its contrast over a busy or bright desktop.
        glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(HUDInk.scrimOpacity)
        glass.contentView = scroll
        contentView = glass
    }
}
