import AppKit
import ZivletCore
import ZivletRuntime
import ZivletSettings
import ZivletUI
import ZivletWheel

/// What the menu's commands do in the app; set by the composition root.
struct MenuHandlers {
    var cancel: (BatchID) -> Void = { _ in }
    var undo: (BatchID) -> Void = { _ in }
    var settings: () -> Void = {}
    var practice: () -> Void = {}
    /// Nil until the updater runs (D-M4-11): Check for Updates… stays disabled.
    var checkForUpdates: (() -> Void)?
}

/// Feeds the status menu (D4): running batches from conversion snapshots, recent results from the undo history,
/// bindings and Pause from settings. Recent results are cached and refreshed after each change, because the menu is
/// built synchronously when it opens.
final class MenuWiring {
    var handlers = MenuHandlers()
    private let settings: SettingsStore
    private let undoHistory: UndoHistory
    private var statusMenu: StatusMenu?
    private var active = ActiveBatches()
    private var recent: [MenuRecent] = []
    private var observer: Task<Void, Never>?

    init(settings: SettingsStore, undoHistory: UndoHistory) {
        self.settings = settings
        self.undoHistory = undoHistory
    }

    func install(wheel: WheelController) {
        let menu = StatusMenu(
            wheel: wheel, state: { [weak self] in self?.state ?? .idle(bindings: .standard) },
            perform: { [weak self] in self?.perform($0) })
        menu.showPaused(settings.current.trigger.paused)
        statusMenu = menu
        let changes = settings.changes
        observer = Task { [weak menu] in
            for await settings in changes { menu?.showPaused(settings.trigger.paused) }
        }
        refreshRecent()
    }

    func track(_ snapshot: BatchSnapshot) {
        active = active.updating(snapshot)
    }

    /// Call after anything that adds to or removes from the undo history.
    func refreshRecent() {
        Task { [undoHistory] in
            let entries = await undoHistory.recent()
            self.recent = entries.map(MenuRecent.init)
        }
    }

    private var state: MenuState {
        let current = settings.current
        return MenuState(
            bindings: current.trigger.bindings, paused: current.trigger.paused, batches: active.menuBatches,
            recent: recent, canCheckForUpdates: handlers.checkForUpdates != nil)
    }

    private func perform(_ action: MenuAction) {
        switch action {
        case .cancel(let batch): handlers.cancel(batch)
        case .reveal(let batch): reveal(batch)
        case .undo(let batch): handlers.undo(batch)
        case .settings: handlers.settings()
        case .practice: handlers.practice()
        case .togglePause: settings.update { $0.with(\.trigger.paused, !$0.trigger.paused) }
        case .checkForUpdates: handlers.checkForUpdates?()
        case .about:
            NSApplication.shared.activate()
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
        case .quit: NSApplication.shared.terminate(nil)
        }
    }

    private func reveal(_ batch: BatchID) {
        let urls = recent.first { $0.batch == batch }?.urls ?? []
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !existing.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(existing) }
    }
}
