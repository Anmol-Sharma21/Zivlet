#if DEBUG
    import AppKit

    /// Dev drop logger surface (05 P0-43): a small non-activating panel at the bottom-right of the main screen that
    /// shows the last selection for 4 s. Debug builds only; Release just logs.
    final class DebugHUD {
        private static let size = NSSize(width: 360, height: 44)
        private let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: DebugHUD.size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        private let label = NSTextField(labelWithString: "")
        private var hideTask: Task<Void, Never>?

        init() {
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
            background.material = .hudWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = 12
            label.font = .systemFont(ofSize: 13, weight: .medium)
            label.alignment = .center
            label.frame = background.bounds.insetBy(dx: 12, dy: 13)
            background.addSubview(label)
            panel.contentView = background
        }

        func show(_ text: String) {
            label.stringValue = text
            if let visible = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: visible.maxX - Self.size.width - 16, y: visible.minY + 16))
            }
            panel.orderFrontRegardless()
            hideTask?.cancel()
            hideTask = Task { [panel] in
                // Sleep throws only on cancellation, which is the "a newer selection arrived" case.
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                panel.orderOut(nil)
            }
        }
    }
#endif
