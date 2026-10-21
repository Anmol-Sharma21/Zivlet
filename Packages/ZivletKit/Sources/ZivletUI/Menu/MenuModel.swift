import Foundation
import ZivletCore
import ZivletTrigger

/// What a menu item does; the status menu maps each to a closure the app provides.
public enum MenuAction: Sendable, Equatable {
    case cancel(BatchID)
    case reveal(BatchID)
    case undo(BatchID)
    case settings, practice, togglePause, checkForUpdates, about, quit
}

/// One menu item as a value. A separator has the title "—"; `children` make a submenu.
public struct MenuEntry: Sendable, Equatable {
    public static let separatorTitle = "—"

    public let title: String
    public let subtitle: String?
    public let action: MenuAction?
    public let isEnabled: Bool
    public let keyEquivalent: String
    public let children: [MenuEntry]

    public var isSeparator: Bool { title == Self.separatorTitle && action == nil }

    init(
        _ title: String, subtitle: String? = nil, action: MenuAction? = nil, isEnabled: Bool = true,
        key: String = "", children: [MenuEntry] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.isEnabled = isEnabled
        keyEquivalent = key
        self.children = children
    }

    static let separator = MenuEntry(separatorTitle, isEnabled: false)

    static func info(_ title: String) -> MenuEntry { MenuEntry(title, isEnabled: false) }
}

/// Everything the status menu shows, gathered when it opens.
public struct MenuState: Sendable, Equatable {
    public let bindings: TriggerBindings
    public let paused: Bool
    public let batches: [MenuBatch]
    public let recent: [MenuRecent]
    public let canCheckForUpdates: Bool

    public init(
        bindings: TriggerBindings, paused: Bool, batches: [MenuBatch], recent: [MenuRecent],
        canCheckForUpdates: Bool = false
    ) {
        self.bindings = bindings
        self.paused = paused
        self.batches = batches
        self.recent = recent
        self.canCheckForUpdates = canCheckForUpdates
    }

    public static func idle(bindings: TriggerBindings, paused: Bool = false, canCheckForUpdates: Bool = false)
        -> MenuState
    {
        MenuState(
            bindings: bindings, paused: paused, batches: [], recent: [], canCheckForUpdates: canCheckForUpdates)
    }
}

/// The status menu (03b §8.3): state line, key summary, running batches, recent results, then the fixed commands.
public enum MenuModel {
    public static let nameLimit = 38
    public static let recentLimit = 10

    public static func make(state: MenuState) -> [MenuEntry] {
        [.info(stateLine(state)), .info(state.bindings.menuSummary)] + batchRows(state.batches)
            + recentRows(state.recent) + commands(state)
    }

    static func stateLine(_ state: MenuState) -> String {
        if state.paused { return "Paused" }
        return state.batches.isEmpty ? "Zivlet is ready" : "Working on \(state.batches.count)"
    }

    private static func batchRows(_ batches: [MenuBatch]) -> [MenuEntry] {
        guard !batches.isEmpty else { return [] }
        return [.separator]
            + batches.map { batch in
                MenuEntry(
                    "\(NameTruncation.middle(batch.name, limit: nameLimit)) — \(batch.percent)%",
                    subtitle: "Click to cancel", action: .cancel(batch.id))
            }
    }

    private static func recentRows(_ recent: [MenuRecent]) -> [MenuEntry] {
        guard !recent.isEmpty else { return [] }
        let rows = recent.prefix(recentLimit).map { entry in
            MenuEntry(
                NameTruncation.middle(entry.title, limit: nameLimit),
                children: [
                    MenuEntry("Show in Finder", action: .reveal(entry.batch)),
                    MenuEntry("Undo", action: .undo(entry.batch)),
                ])
        }
        return [.separator, MenuEntry("Recent Results", children: Array(rows))]
    }

    private static func commands(_ state: MenuState) -> [MenuEntry] {
        [
            .separator, MenuEntry("Settings…", action: .settings, key: ","),
            MenuEntry("Practice…", action: .practice),
            MenuEntry(state.paused ? "Resume Zivlet" : "Pause Zivlet", action: .togglePause),
            MenuEntry("Check for Updates…", action: .checkForUpdates, isEnabled: state.canCheckForUpdates),
            .separator, MenuEntry("About Zivlet", action: .about), MenuEntry("Quit Zivlet", action: .quit, key: "q"),
        ]
    }
}
