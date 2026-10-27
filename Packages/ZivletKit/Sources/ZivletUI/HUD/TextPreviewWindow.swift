import AppKit
import ZivletActions

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
/// on the solid window background with a 1 pt outline under Reduce Transparency or Increase Contrast (the rule of
/// every Zivlet surface, D-NL3, D-BL2), and it follows a change of either at once (19b §7). Escape and ⌘W close it;
/// ⌘A and ⌘C select and copy (for this Mac only), since Zivlet has no main menu. It keeps the text only while it is
/// open: closing it empties the view. It is an AppKit window around an `NSTextView`, so its glass is
/// `NSGlassEffectView`: the SwiftUI glass of the island and the HUDs (19b D-NL2) has no text view (D-M6-21).
public final class TextPreviewWindow: NSPanel {
    static let size = CGSize(width: 520, height: 420)
    static let inset = CGSize(width: 16, height: 14)
    static let outlineWidth: CGFloat = 1

    let textView: NSTextView
    private let scroll: NSScrollView
    private let clipboard: ClipboardAction
    private var displayOptions: (any NSObjectProtocol)?

    /// `clipboard` is the general pasteboard; tests pass a private one.
    public init(clipboard: ClipboardAction = ClipboardAction()) {
        self.clipboard = clipboard
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
        let workspace = NSWorkspace.shared
        applyBackground(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
        displayOptions = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displayOptionsChanged() }
        }
    }

    isolated deinit {
        if let displayOptions { NSWorkspace.shared.notificationCenter.removeObserver(displayOptions) }
    }

    override public var canBecomeKey: Bool { true }

    /// Glass unless Reduce Transparency or Increase Contrast asks for a solid surface.
    static func usesGlass(reduceTransparency: Bool, increaseContrast: Bool = false) -> Bool {
        !reduceTransparency && !increaseContrast
    }

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
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": close()
        case "a": textView.selectAll(nil)
        case "c": copySelection()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    /// The selected text to the clipboard, for this Mac only, like Copy Text itself; nothing selected copies nothing.
    func copySelection() {
        let range = textView.selectedRange()
        guard range.length > 0 else { return }
        _ = clipboard.copyText((textView.string as NSString).substring(with: range))
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

    private func displayOptionsChanged() {
        let workspace = NSWorkspace.shared
        applyBackground(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast)
    }

    /// Glass, or the solid window background; Increase Contrast adds the 1 pt outline. Applied again whenever the
    /// display options change.
    func applyBackground(reduceTransparency: Bool, increaseContrast: Bool) {
        let frame = contentView?.frame ?? NSRect(origin: .zero, size: Self.size)
        scroll.removeFromSuperview()
        guard Self.usesGlass(reduceTransparency: reduceTransparency, increaseContrast: increaseContrast) else {
            isOpaque = true
            backgroundColor = .windowBackgroundColor
            scroll.drawsBackground = true
            scroll.backgroundColor = .windowBackgroundColor
            let solid = NSView(frame: frame)
            solid.wantsLayer = true
            solid.layer?.borderWidth = increaseContrast ? Self.outlineWidth : 0
            solid.layer?.borderColor = NSColor.labelColor.cgColor
            scroll.frame = solid.bounds
            solid.addSubview(scroll)
            contentView = solid
            return
        }
        isOpaque = false
        backgroundColor = .clear
        scroll.drawsBackground = false
        let glass = NSGlassEffectView(frame: frame)
        glass.cornerRadius = HUDInk.cornerRadius
        // The HUD's scrim, as a tint: the text holds its contrast over a busy or bright desktop.
        glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(HUDInk.scrimOpacity)
        glass.contentView = scroll
        contentView = glass
    }

    /// The surface drawn now has the outline (Increase Contrast).
    var hasOutline: Bool { (contentView?.layer?.borderWidth ?? 0) > 0 }
}
