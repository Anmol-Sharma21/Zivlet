#if DEBUG
    import AppKit
    import ZivletNotch
    import ZivletUI
    import os

    /// Screenshot-only set-up for the island (plan 14 D-ND4): the flags that force a finish or the pill, and a plain
    /// panel under the island for contrast readings. Debug builds only.
    enum IslandShots {
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "hud")

        /// The flags from the launch arguments; refused flags are logged and ignored.
        static func flags(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> IslandShotFlags {
            do {
                return try IslandShotFlags.parse(arguments: arguments)
            } catch {
                logger.error("Island screenshot flags refused: \(String(describing: error), privacy: .private)")
                return IslandShotFlags()
            }
        }

        /// Every display without its notch when the pill is forced, else the live screens.
        static func reader(_ flags: IslandShotFlags) -> ScreenGeometryReader {
            guard flags.pill else { return ScreenGeometryReader() }
            return ScreenGeometryReader(screens: { ScreenGeometryReader.live().map(\.withoutNotch) })
        }
    }

    /// A white or black panel across the top middle of the menu-bar display, below the island and above other
    /// windows, so the glass is read over a known backdrop.
    final class IslandBackdrop {
        static let size = NSSize(width: 900, height: 480)
        private let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: IslandBackdrop.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)

        init(_ backdrop: IslandShotFlags.Backdrop) {
            panel.level = .floating
            panel.isOpaque = true
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = backdrop == .white ? .white : .black
        }

        func show() {
            guard let screen = NSScreen.screens.first else { return }
            let frame = screen.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size.width / 2, y: frame.maxY - Self.size.height))
            panel.orderFrontRegardless()
        }
    }
#endif
