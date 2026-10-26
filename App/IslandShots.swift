#if DEBUG || ZIVLET_ISLAND_PREVIEW
    import AppKit
    import ZivletNotch
    import ZivletUI
    import os

    /// Screenshot-only set-up for the island (plan 14 D-ND4): the flags that force a finish or the pill, and a plain
    /// panel under the island for contrast readings. Debug builds only.
    enum IslandShots {
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "hud")

        /// The flags from the launch arguments. A refusal is logged in public (it names the flag only), so
        /// `demo-notch-states.sh` can fail the capture instead of saving the wrong state, and every flag is ignored.
        static func flags(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> IslandShotFlags {
            do {
                return try IslandShotFlags.parse(arguments: arguments)
            } catch {
                logger.error("Island screenshot flags refused: \(error.logDescription, privacy: .public)")
                return IslandShotFlags()
            }
        }

        /// Every display without its notch when the pill is forced, else the live screens.
        static func reader(_ flags: IslandShotFlags) -> ScreenGeometryReader {
            guard flags.pill else { return ScreenGeometryReader() }
            return ScreenGeometryReader(screens: { ScreenGeometryReader.live().map(\.withoutNotch) })
        }
    }

    /// A white or black panel over the whole menu-bar display, below the island and the Drop Box and above other
    /// windows, so the glass is read over a known backdrop wherever it sits (the docked tab is on the display's edge).
    final class IslandBackdrop {
        private let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
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
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
        }
    }
#endif
