#if DEBUG
    import AppKit
    import ZivletActions
    import ZivletCore
    import os

    /// DEBUG `-ZivletCopyTextDemo <folder>` (plan 18d D15, exit row Z7): Copy Text through the drop path on the inputs
    /// `Scripts/demo-copy-text.sh` rendered into `<folder>` (fixture 05 as `05_mixed.png`, the mixed sentence as
    /// `mixed.pdf`, and `blank.png`): once plainly, once with Option, then on the blank image. The text goes to a
    /// private pasteboard, never the person's clipboard, and the languages are "Hindi and English" for the run. Each
    /// step writes `<step>.json` (the result's kind and toast, the copied text, the saved files) into the folder, which
    /// the script made; `done` marks the end.
    struct CopyTextDemo {
        static let flag = "-ZivletCopyTextDemo"
        static let pasteboard = NSPasteboard(name: NSPasteboard.Name("app.zivlet.Zivlet.copy-text-demo"))
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")

        let folder: URL

        /// An existing absolute folder after the flag, or nil.
        static func parse(arguments: [String]) -> CopyTextDemo? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            let path = arguments[index + 1]
            var isFolder: ObjCBool = false
            guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isFolder),
                isFolder.boolValue
            else { return nil }
            return CopyTextDemo(folder: URL(fileURLWithPath: path, isDirectory: true))
        }

        static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(flag) }

        /// The fixtures are Hindi and English: "Match my languages" would read English only on a Mac whose languages and
        /// keyboards have no Hindi (the P2-103 rule), so the demo picks "Hindi and English" for this run only.
        @MainActor func run(tools: ToolWiring) async {
            tools.choiceOverride = .hindiAndEnglish
            let image = folder.appending(path: "05_mixed.png")
            let pdf = folder.appending(path: "mixed.pdf")
            await step("plain", urls: [image, pdf], optionHeld: false, tools: tools)
            await step("option", urls: [image, pdf], optionHeld: true, tools: tools)
            await step("blank", urls: [folder.appending(path: "blank.png")], optionHeld: false, tools: tools)
            FileManager.default.createFile(atPath: folder.appending(path: "done").path, contents: Data())
        }

        @MainActor private func step(_ name: String, urls: [URL], optionHeld: Bool, tools: ToolWiring) async {
            Self.pasteboard.clearContents()
            guard let task = tools.run(.copyText, urls: urls, optionHeld: optionHeld, near: nil) else { return }
            let result = await task.value
            let report: [String: Any] = [
                "kind": Self.kind(result), "toast": result.toast ?? result.card?.title ?? "",
                "clipboard": Self.pasteboard.string(forType: .string) ?? "",
                "saved": result.text?.savedFiles.map(\.path) ?? [],
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                try data.write(to: folder.appending(path: "\(name).json"))
                Self.logger.notice("Copy Text demo step \(name, privacy: .public) written")
            } catch {
                Self.logger.error("Copy Text demo step \(name, privacy: .public) not written")
            }
        }

        static func kind(_ result: ActionResult) -> String {
            switch result {
            case .text: "text"
            case .done: "done"
            case .partial: "partial"
            case .failed: "failed"
            case .cancelled: "cancelled"
            case .working: "working"
            }
        }
    }
#endif
