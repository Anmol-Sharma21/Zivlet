#if DEBUG
    import AppKit
    import ZivletActions
    import ZivletCore
    import ZivletUI
    import os

    /// DEBUG `-ZivletLockedInputDemo <folder>` (plan 20g F3, exit row V10, P2-107): COPY TEXT through the drop path on
    /// `<folder>/Locked.pdf`, which the script made, with a scripted prompter answering the Unlock sheet with the first
    /// line of `<folder>/secret` (a 0600 file deleted once read, `DemoSecrets`). The text goes to the Copy Text demo's
    /// private pasteboard, never the person's clipboard. `locked.json` holds the sheets asked for, the result's kind
    /// and toast and the copied text; `done` marks the end.
    struct LockedInputDemo {
        static let flag = "-ZivletLockedInputDemo"
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")

        let folder: URL

        static func parse(arguments: [String]) -> LockedInputDemo? {
            DemoFolder.parse(flag, arguments: arguments).map(LockedInputDemo.init(folder:))
        }

        static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(flag) }

        @MainActor func run(tools: ToolWiring) async {
            defer { DemoFolder.finish(folder) }
            guard let password = DemoSecrets.read(in: folder)?.first else {
                return Self.logger.error("Locked input demo: no secret file")
            }
            let earlier = tools.prompter
            let prompter = ScriptedPrompter([
                .secrets(JobSecrets(input: JobSecret(utf8: password)), sameForAll: true)
            ])
            tools.prompter = prompter
            defer { tools.prompter = earlier }
            CopyTextDemo.pasteboard.clearContents()
            let file = folder.appending(path: "Locked.pdf")
            guard let task = tools.run(.copyText, urls: [file], optionHeld: false, near: nil) else {
                return Self.logger.error("Locked input demo: Copy Text did not start")
            }
            let result = await task.value
            let report: [String: Any] = [
                "asked": prompter.modes, "kind": CopyTextDemo.kind(result),
                "toast": result.toast ?? result.card?.title ?? "",
                "clipboard": CopyTextDemo.pasteboard.string(forType: .string) ?? "",
            ]
            DemoFolder.write(report, named: "locked", in: folder, logger: Self.logger)
        }
    }
#endif
