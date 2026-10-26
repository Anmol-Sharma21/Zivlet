#if DEBUG
    import AppKit
    import SwiftUI
    import ZivletBox
    import ZivletCore
    import ZivletShelfCore
    import ZivletUI
    import os

    /// Screenshot and demo set-up for the Drop Box (plan 16 D-M5b-20). Debug builds only; a Release binary that
    /// carries either flag fails `check-release-paths.sh`.
    enum BoxShots {
        static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "hud")
        static let demoFolderName = ".zivlet-box-demo"

        /// The flags from the launch arguments. A refusal is logged in public (it names the flag only) and every box
        /// flag is ignored.
        static func flags(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> BoxShotFlags {
            do {
                return try BoxShotFlags.parse(arguments: arguments)
            } catch {
                logger.error("Box screenshot flags refused: \(error.logDescription, privacy: .public)")
                return BoxShotFlags()
            }
        }

        /// The demo keeps its box in a store inside the demo folder, so a relaunch finds it again; a preview uses an
        /// empty store in a temporary folder. Neither touches the person's `boxes.json`.
        static func ports(_ flags: BoxShotFlags) -> BoxPorts {
            let standard = BoxPorts.standard()
            let root: URL
            if let folder = flags.demoFolder, isFolder(folder) {
                root = folder.appending(path: demoFolderName, directoryHint: .isDirectory)
            } else if flags.preview != nil || flags.demoFolder != nil {
                root = FileManager.default.temporaryDirectory.appending(path: "zivlet-box-preview-\(UUID().uuidString)")
            } else {
                return standard
            }
            return standard.with(
                store: BoxStore(file: root.appending(path: "boxes.json")),
                storage: OwnedStorage(root: root.appending(path: "Box", directoryHint: .isDirectory)))
        }

        /// Runs the preview or the demo the flags ask for, after the box has started.
        @MainActor
        static func run(_ flags: BoxShotFlags, controller: BoxController, finish: BoxFinish) -> BoxPreviewPanel? {
            if let folder = flags.demoFolder { demo(folder, controller: controller) }
            guard let state = flags.preview else { return nil }
            let preview = BoxPreviewPanel()
            preview.show(state, finish: finish, icon: { controller.placeholder(forName: $0) })
            return preview
        }

        /// Adds the folder's visible files to the demo box and shows it; logs what the demo script waits for.
        @MainActor
        private static func demo(_ folder: URL, controller: BoxController) {
            guard isFolder(folder) else {
                logger.error("Box demo refused: the folder does not exist")
                return
            }
            let restored = controller.current?.items.count ?? 0
            if restored > 0 { logger.notice("Box: restored \(restored, privacy: .public) items") }
            let files =
                (try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
            let regular = files.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            Task {
                _ = await controller.add(regular.sorted { $0.path < $1.path }, newBox: false)
                controller.showPanel(.saved)
                logger.notice("Box: shown")
                logger.notice("Box: items \(controller.current?.items.count ?? 0, privacy: .public)")
            }
        }

        private static func isFolder(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    /// One Drop Box state with made-up items, in its own panel near the top middle of the menu-bar display (over the
    /// island backdrop) or, docked, against the right edge.
    @MainActor
    final class BoxPreviewPanel {
        static let topInset: CGFloat = 120
        let panel = BoxPanel()

        func show(_ state: BoxShotFlags.State, finish: BoxFinish, icon: (String) -> NSImage) {
            guard let screen = NSScreen.screens.first else { return }
            let visible = screen.visibleFrame
            let model = BoxPreview.model(
                state, finish: finish, maxHeight: CGFloat(PanelFrames.maxHeight(in: Rect2D(visible))), icon: icon)
            BoxShots.logger.notice("Box: \(state.rawValue, privacy: .public)")
            let size = BoxLayout.size(of: model)
            guard size != .zero else { return }
            panel.contentView = NSHostingView(rootView: BoxPanelView(model: model) { _ in })
            let origin =
                state == .docked
                ? NSPoint(x: visible.maxX - size.width, y: visible.midY - size.height / 2)
                : NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - Self.topInset - size.height)
            let frame = NSRect(origin: origin, size: size)
            panel.setFrame(frame, display: true)
            panel.show()
            BoxShots.logger.notice("\(BoxPreview.frameLine(frame, screenTop: screen.frame.maxY), privacy: .public)")
        }
    }
#endif
