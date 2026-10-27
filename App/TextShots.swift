#if DEBUG
    import AppKit
    import EngineVision
    import ZivletActions
    import ZivletUI
    import os

    /// DEBUG `-ZivletTextStates <state>` (plan 18d D15, exit row Z9): one Copy Text state on screen for
    /// `Scripts/demo-text-states.sh`, with made-up text in Zivlet's own words: the island's toast or card, the card
    /// near the drop, or Show All. The island logs its own frame; the others log `Text shot: <state>` and
    /// `Text shot: frame x y w h` in screen-capture points (top left of the menu-bar display, y down).
    enum TextShots {
        enum State: String, CaseIterable {
            case notchToast, notchCard, hudCard, showAll
        }

        static let flag = "-ZivletTextStates"
        static let sampleText = "Train का टिकट book कर दिया है,\nplatform नंबर 4 पर मिलना।\nGate 2 से entry है।"
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")

        static func parse(arguments: [String]) -> State? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return State(rawValue: arguments[index + 1])
        }

        static var sample: ActionResult {
            let text = TextAssembly.combine([FileText(name: "ticket.png", pages: [RecognizedPage(text: sampleText)])])
            return ToolWiringModel.result(text, sources: [URL(fileURLWithPath: "/tmp/ticket.png")])
        }

        @MainActor static func run(_ state: State, island: IslandWiring, actions: ActionWiring, tools: ToolWiring) {
            switch state {
            case .notchToast:
                island.hud.show(sample, near: nil)
            case .notchCard:
                island.hud.show(sample, near: nil)
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    island.hosts.expandRequested()
                }
            case .hudCard:
                let center = NSScreen.screens.first.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? .zero
                actions.showNearDrop(sample, near: center)
                logFrame(state) { actions.nearDropFrame }
            case .showAll:
                let outcome = sample.text
                tools.preview.show(TextPreviewModel(title: outcome?.windowTitle ?? "", text: outcome?.fullText ?? ""))
                logFrame(state) { tools.preview.frame }
            }
        }

        /// After the panel has laid out, its frame in screen-capture points.
        @MainActor private static func logFrame(_ state: State, frame: @escaping @MainActor () -> CGRect) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                let rect = frame()
                guard let top = NSScreen.screens.first?.frame.maxY else { return }
                let (x, y) = (Int(rect.minX.rounded()), Int((top - rect.maxY).rounded()))
                let (width, height) = (Int(rect.width.rounded()), Int(rect.height.rounded()))
                logger.notice("Text shot: \(state.rawValue, privacy: .public)")
                logger.notice(
                    "Text shot: frame \(x, privacy: .public) \(y, privacy: .public) \(width, privacy: .public) \(height, privacy: .public)"
                )
            }
        }
    }
#endif
