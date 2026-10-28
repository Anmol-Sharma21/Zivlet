import AppKit
import ZivletActions
import ZivletCore
import ZivletUI
import os

/// The tool window in the app (P2-30, plan 20b A5): one `ToolWindow`, made when a window tool first needs it, driven
/// by `ToolWindowCoordinator`. `contents` gives each window tool its content; none has one yet (Lock · Unlock joins
/// in stream E), so every editor tool still falls through to the DEBUG note. A refusal (a single-file tool with
/// several files) goes to the action presenter, near the drop or on the island as the placement says.
@MainActor
final class ToolWindowWiring {
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")
    private var window: ToolWindow?
    private(set) lazy var coordinator = ToolWindowCoordinator(
        makeWindow: { [weak self] in
            let window = ToolWindow()
            #if DEBUG
                window.finishOverride = IslandShots.flags().finish
            #endif
            self?.window = window
            return window
        },
        contents: { [weak self] tool, urls in self?.content(for: tool, urls: urls) },
        refuse: { [weak self] result, point in self?.actions.present(result, near: point) })
    private let actions: ActionWiring

    init(actions: ActionWiring) {
        self.actions = actions
    }

    /// Opens `tool`'s window; false when the tool has no window content.
    func open(_ tool: ToolID, urls: [URL], near point: CGPoint?) -> Bool {
        let opened = coordinator.open(tool, urls: urls, near: point)
        if opened, coordinator.isOpen { logShown(tool.rawValue) }
        return opened
    }

    /// Read QR's results; they replace earlier results but never another tool's open window.
    func present(results: CodeResultsContent, near point: CGPoint?) -> Bool {
        let shown = coordinator.present(results, near: point) { $0 is CodeResultsContent }
        if shown { logShown("results") }
        return shown
    }

    /// The tool's identifier and the window's number, for the demo captures; never a file name or a code.
    private func logShown(_ kind: String) {
        let number = window?.windowNumber ?? 0
        logger.notice("Tool window shown: \(kind, privacy: .public) window \(number, privacy: .public)")
    }

    private func content(for tool: ToolID, urls: [URL]) -> (any WindowToolContent)? {
        nil
    }
}
