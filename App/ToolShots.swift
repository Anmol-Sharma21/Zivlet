#if DEBUG
    import AppKit
    import EngineVision
    import ZivletActions
    import ZivletCore
    import ZivletNotch
    import ZivletRuntime
    import ZivletUI
    import os

    /// DEBUG `-ZivletToolStates <state>` (plan 20g F3, exit row V11): one M7 state on screen with made-up content in
    /// Zivlet's own words, for `Scripts/demo-tool-states.sh`. `qrResults` is Read QR's results window at the main
    /// screen's centre (three codes from two files, one web link with Open, one other link); the four card states are
    /// a finished LOCK · UNLOCK batch on the island with `-ZivletHUDPlacement notch` (its card opened after a second),
    /// else on the card near the drop.
    /// Nothing is read or written: the batch's files are names only. Logs `Tool shot: <state>` and
    /// `Tool shot: window <n> frame x y w h` once the surface shows.
    enum ToolShots {
        enum State: String, CaseIterable {
            case qrResults, lockCard, unlockCard, changeCard, wrongCard
        }

        static let flag = "-ZivletToolStates"
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")
        private static let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "zivlet-tool-shots")

        static func parse(arguments: [String]) -> State? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return State(rawValue: arguments[index + 1])
        }

        @MainActor static func run(
            _ state: State, toolWindows: ToolWindowWiring, island: IslandWiring, conversion: ConversionWiring,
            atNotch: Bool
        ) {
            if state == .qrResults { return showResults(toolWindows) }
            guard let snapshot = try? card(state) else { return logger.error("Tool shot: no batch for the card") }
            if atNotch {
                island.hud.prepare(near: nil)
                island.hud.show(snapshot)
                // Open the island's card after a second, as a person's hover would.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    island.hosts.expandRequested()
                    logWindow(state, after: .milliseconds(900)) { ShotFrame.visible(IslandPanel.self) }
                }
                return
            }
            conversion.hud.show(snapshot)
            logWindow(state) { ShotFrame.visible(HUDWindow.self) }
        }

        @MainActor private static func showResults(_ toolWindows: ToolWindowWiring) {
            let files = [
                FileCodes(
                    name: "Cafe menu.pdf",
                    codes: [
                        FoundCode(payload: "https://example.com/zivlet/menu", symbology: "qr", page: 1),
                        FoundCode(payload: "mailto:hello@example.com", symbology: "qr", page: 2),
                    ]),
                FileCodes(
                    name: "Shelf label.png",
                    codes: [FoundCode(payload: "ZV-2026-0042", symbology: "code128", page: nil)]),
            ]
            guard case .window(let model) = CodeResults.present(files) else { return }
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("app.zivlet.tool-shots"))
            let content = CodeResultsContent(model: model, clipboard: ClipboardAction(pasteboard: pasteboard)) { _ in }
            let center = NSScreen.main.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) }
            _ = toolWindows.present(results: content, near: center)
            logWindow(.qrResults) { ShotFrame.visible(ToolWindow.self) }
        }

        /// A one-file LOCK · UNLOCK batch that ended as the state says.
        private static func card(_ state: State) throws -> BatchSnapshot {
            let mode: ProtectSpec.Mode =
                switch state {
                case .lockCard: .lock(nil)
                case .changeCard: .changePassword
                default: .unlock
                }
            let input = try InputItem(url: folder.appending(path: "Budget 2026.pdf"), format: .pdf, byteCount: 184_320)
            let request = try JobRequest(
                input: input, operation: .protect(ProtectSpec(mode: mode)), destination: folder)
            let batch = BatchID()
            let output = OutputNamer().protect(source: input.fileName, mode: mode).rendered()
            let published = PublishedOutput(
                url: folder.appending(path: output), format: .pdf, byteCount: 186_880, fileID: 0, modified: Date())
            let end: JobState = state == .wrongCard ? .failed(.wrongPassword) : .succeeded(published)
            let plan = RequestPlan(requests: [request], rejections: [])
            return BatchSnapshot(batch: batch, target: .pdf, plan: plan, protect: mode)
                .applying(.changed(batch, request.id, end)).applying(.finished(batch))
        }

        @MainActor private static func logWindow(
            _ state: State, after delay: Duration = .milliseconds(600), window: @escaping @MainActor () -> NSWindow?
        ) {
            Task { @MainActor in
                try? await Task.sleep(for: delay)
                logger.notice("Tool shot: \(state.rawValue, privacy: .public)")
                if let window = window() { ShotFrame.log("Tool shot", window, logger: logger) }
            }
        }
    }
#endif
