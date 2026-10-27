#if DEBUG
    import AppKit
    import Synchronization
    import ZivletActions
    import ZivletBox
    import ZivletCore
    import ZivletRuntime
    import ZivletUI
    import os

    /// DEBUG `-ZivletBoxBusyDemo <folder>` (plan 18e E2, exit row Z8): a cancelled Move from the Drop Box, with Undo.
    /// It makes 50 files in `<folder>/source`, adds them to a demo box kept inside the folder (never `boxes.json`),
    /// and moves them to `<folder>/moved` without the folder panel, paced so the bar can be seen. After the 20th file
    /// it holds, writes `hold.json` (the panel's frame) and waits for the script's `captured`; then it presses Cancel,
    /// runs Undo on the result, writes `result.json` and `done`. `Scripts/demo-box-busy.sh` made the folder.
    @MainActor
    final class BoxBusyDemo {
        static let flag = "-ZivletBoxBusyDemo"
        static let fileCount = 50
        static let stopAfter = 20
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "hud")

        let folder: URL
        private var source: URL { folder.appending(path: "source", directoryHint: .isDirectory) }
        private var moved: URL { folder.appending(path: "moved", directoryHint: .isDirectory) }
        private var pending: CheckedContinuation<ActionResult, Never>?
        private weak var box: BoxWiring?

        private init(folder: URL) { self.folder = folder }

        /// An existing absolute folder after the flag, or nil.
        static func parse(arguments: [String] = ProcessInfo.processInfo.arguments) -> BoxBusyDemo? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            let path = arguments[index + 1]
            var isFolder: ObjCBool = false
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isFolder),
                isFolder.boolValue
            else { return nil }
            return BoxBusyDemo(folder: URL(fileURLWithPath: path, isDirectory: true))
        }

        /// The demo box's stores, inside the folder (as the Y4 demo's).
        func ports() -> BoxPorts { BoxShots.ports(BoxShotFlags(demoFolder: folder)) }

        /// Move to… with `moved` as the answer and the paced executor; the undo history is the app's.
        func service(undoHistory: UndoHistory) -> ActionService {
            let pacer = BusyPacer(
                stopAfter: Self.stopAfter, captured: folder.appending(path: "captured"),
                hold: { [weak self] done in DispatchQueue.main.sync { MainActor.assumeIsolated { self?.hold(done) } } },
                stop: { [weak self] in
                    DispatchQueue.main.sync { MainActor.assumeIsolated { self?.box?.controller.press(.cancelBusy) } }
                })
            return ActionService(
                folders: FixedFolder(url: moved), executor: MoveExecutor(rename: pacer.rename),
                undoHistory: undoHistory)
        }

        /// Every box result passes here; the one after the Move press ends the wait.
        func received(_ result: ActionResult) {
            pending?.resume(returning: result)
            pending = nil
        }

        /// Runs the demo on the app's box, then Undo through the app's own undo path.
        func run(box: BoxWiring, undo: @escaping (BatchID) async -> UndoReply) async {
            self.box = box
            let files: [URL]
            do {
                files = try makeFiles()
            } catch {
                return finish(["error": "the files were not made"])
            }
            _ = await box.controller.add(files, newBox: false)
            box.controller.showPanel(.saved)
            Self.logger.notice("Box busy demo: items \(box.controller.current?.items.count ?? 0, privacy: .public)")
            let result = await withCheckedContinuation { continuation in
                pending = continuation
                box.controller.press(.moveTo)
            }
            var report = summary(result)
            if let batch = result.undo { report["undo"] = await undo(batch).message }
            report["sourceAfterUndo"] = count(source)
            report["movedAfterUndo"] = count(moved)
            finish(report)
        }

        private func makeFiles() throws -> [URL] {
            let manager = FileManager.default
            try manager.createDirectory(at: source, withIntermediateDirectories: false)
            try manager.createDirectory(at: moved, withIntermediateDirectories: false)
            return try (1...Self.fileCount).map { index in
                let url = source.appending(path: String(format: "item-%02d.txt", index))
                try Data("Zivlet box demo item \(index)\n".utf8).write(to: url, options: .withoutOverwriting)
                return url
            }
        }

        private func summary(_ result: ActionResult) -> [String: Any] {
            [
                "kind": CopyTextDemo.kind(result), "toast": result.toast ?? "", "card": result.card?.title ?? "",
                "movedBeforeUndo": count(moved), "leftBeforeUndo": count(source),
            ]
        }

        /// After the 20th file: the panel's frame (points from the top left of the menu-bar display) for the capture.
        private func hold(_ done: Int) {
            var report: [String: Any] = ["done": done, "total": Self.fileCount]
            if let frame = box?.lastFrame, let top = NSScreen.screens.first?.frame.maxY {
                let values = [frame.minX, top - frame.maxY, frame.width, frame.height].map { Int($0.rounded()) }
                report["frame"] = values.map(String.init).joined(separator: " ")
            }
            write(report, to: "hold.json")
        }

        private func finish(_ report: [String: Any]) {
            write(report, to: "result.json")
            FileManager.default.createFile(atPath: folder.appending(path: "done").path, contents: Data())
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        }

        private func write(_ report: [String: Any], to name: String) {
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                try data.write(to: folder.appending(path: name))
                Self.logger.notice("Box busy demo: \(name, privacy: .public) written")
            } catch {
                Self.logger.error("Box busy demo: \(name, privacy: .public) not written")
            }
        }

        private func count(_ dir: URL) -> Int {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return names.filter { !$0.hasPrefix(".") }.count
        }
    }

    /// The demo's destination: always the same folder, no panel.
    private struct FixedFolder: FolderChoosing {
        let url: URL
        func chooseFolder(for items: [MoveItem]) async -> URL? { url }
    }

    /// Renames as Move to… does, a little slower, and after the `stopAfter`th item holds until the script has its
    /// picture (or 30 s pass), then stops the run. It runs on the executor's thread, so the waits block no UI.
    nonisolated private final class BusyPacer: Sendable {
        static let pace = 0.03
        static let holdLimit = 30.0
        private let stopAfter: Int
        private let captured: URL
        private let hold: @Sendable (Int) -> Void
        private let stop: @Sendable () -> Void
        private let done = Mutex(0)

        init(
            stopAfter: Int, captured: URL, hold: @escaping @Sendable (Int) -> Void,
            stop: @escaping @Sendable () -> Void
        ) {
            self.stopAfter = stopAfter
            self.captured = captured
            self.hold = hold
            self.stop = stop
        }

        func rename(_ source: URL, _ target: URL) -> Int32? {
            let failure = MoveExecutor.renameExclusive(source, target)
            let count = done.withLock { value in
                value += 1
                return value
            }
            Thread.sleep(forTimeInterval: Self.pace)
            if count == stopAfter {
                hold(count)
                let deadline = Date(timeIntervalSinceNow: Self.holdLimit)
                while !FileManager.default.fileExists(atPath: captured.path), Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                stop()
            }
            return failure
        }
    }
#endif
