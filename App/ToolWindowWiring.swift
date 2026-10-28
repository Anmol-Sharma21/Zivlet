import AppKit
import ZivletActions
import ZivletCore
import ZivletUI

/// The tool window in the app (P2-30, plan 20b A5): one `ToolWindow`, made when a window tool first needs it, driven
/// by `ToolWindowCoordinator`. `contents` gives each window tool its content; none has one yet (Lock · Unlock joins
/// in stream E), so every editor tool still falls through to the DEBUG note. A refusal (a single-file tool with
/// several files) goes to the action presenter, near the drop or on the island as the placement says.
@MainActor
final class ToolWindowWiring {
    private(set) lazy var coordinator = ToolWindowCoordinator(
        makeWindow: { ToolWindow() },
        contents: { [weak self] tool, urls in self?.content(for: tool, urls: urls) },
        refuse: { [weak self] result, point in self?.actions.present(result, near: point) })
    private let actions: ActionWiring

    init(actions: ActionWiring) {
        self.actions = actions
    }

    /// Opens `tool`'s window; false when the tool has no window content.
    func open(_ tool: ToolID, urls: [URL], near point: CGPoint?) -> Bool {
        coordinator.open(tool, urls: urls, near: point)
    }

    private func content(for tool: ToolID, urls: [URL]) -> (any WindowToolContent)? {
        nil
    }
}
