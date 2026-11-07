#if DEBUG
    import AppKit
    import ZivletCore
    import ZivletUI
    import os

    /// Answers each sheet in order, as a person would, and records which sheets were asked for (the DEBUG demos of
    /// plan 20g F3). An empty list answers Cancel.
    @MainActor
    final class ScriptedPrompter: PasswordPrompting {
        private var answers: [PasswordAnswer]
        private(set) var modes: [String] = []

        init(_ answers: [PasswordAnswer]) { self.answers = answers }

        func ask(_ request: PasswordRequest) async -> PasswordAnswer {
            modes.append("\(request.mode)")
            return answers.isEmpty ? .cancelled : answers.removeFirst()
        }

        func retry(_ request: PasswordRequest, failed: [String]) async -> PasswordAnswer {
            modes.append("retry")
            return answers.isEmpty ? .cancelled : answers.removeFirst()
        }
    }

    /// The passwords of a DEBUG demo (plan 20g F3): the lines of `<folder>/secret`, a 0600 file the demo script wrote,
    /// removed here whether or not it could be read, so no password is ever in argv or the environment.
    enum DemoSecrets {
        static let fileName = "secret"
        static let maxLines = 8

        /// The file's lines, or nil when it is missing, not 0600, empty, too long or not UTF-8.
        static func read(in folder: URL) -> [String]? {
            let file = folder.appending(path: fileName)
            defer { try? FileManager.default.removeItem(at: file) }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                (attributes[.posixPermissions] as? Int) == 0o600,
                let text = try? String(contentsOf: file, encoding: .utf8)
            else { return nil }
            let lines = text.split(separator: "\n").map(String.init)
            guard !lines.isEmpty, lines.count <= maxLines, lines.allSatisfy({ !$0.isEmpty }) else { return nil }
            return lines
        }
    }

    /// A demo's folder from `flag <folder>`: an existing absolute directory, else nil.
    enum DemoFolder {
        static func parse(_ flag: String, arguments: [String]) -> URL? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            let path = arguments[index + 1]
            var isFolder: ObjCBool = false
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isFolder),
                isFolder.boolValue
            else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }

        /// Writes `<name>.json` into the folder; logs the step's name only.
        static func write(_ report: [String: Any], named name: String, in folder: URL, logger: Logger) {
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                try data.write(to: folder.appending(path: "\(name).json"))
                logger.notice("Demo step \(name, privacy: .public) written")
            } catch {
                logger.error("Demo step \(name, privacy: .public) not written")
            }
        }

        static func finish(_ folder: URL) {
            FileManager.default.createFile(atPath: folder.appending(path: "done").path, contents: Data())
        }
    }

    /// A window's number and frame (screen-capture points: top left of the menu-bar display, y down), logged as
    /// `<prefix>: window <n> frame x y w h`. Demo scripts capture the window by its number (`screencapture -l`), so a
    /// capture never holds another app's window.
    enum ShotFrame {
        @MainActor static func log(_ prefix: String, _ window: NSWindow, logger: Logger) {
            let rect = window.frame
            guard let top = NSScreen.screens.first?.frame.maxY, rect.width > 0 else { return }
            let (x, y) = (Int(rect.minX.rounded()), Int((top - rect.maxY).rounded()))
            let (width, height) = (Int(rect.width.rounded()), Int(rect.height.rounded()))
            let number = window.windowNumber
            logger.notice(
                "\(prefix, privacy: .public): window \(number, privacy: .public) frame \(x, privacy: .public) \(y, privacy: .public) \(width, privacy: .public) \(height, privacy: .public)"
            )
        }

        /// The first visible window of Zivlet's of the given kind.
        @MainActor static func visible<Window: NSWindow>(_ kind: Window.Type) -> Window? {
            NSApp.windows.lazy.compactMap { $0 as? Window }.first { $0.isVisible }
        }
    }
#endif
