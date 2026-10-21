import AppKit
import ZivletCore
import ZivletUI
import ZivletWheel

/// Status item and menu (14 §3.1, 03b §8.3). The menu is rebuilt from `MenuModel` each time it opens, so it always
/// shows the current state; each item's action goes to `perform`.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let state: () -> MenuState
    private let perform: (MenuAction) -> Void
    private weak var wheel: WheelController?

    init(wheel: WheelController, state: @escaping () -> MenuState, perform: @escaping (MenuAction) -> Void) {
        self.wheel = wheel
        self.state = state
        self.perform = perform
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        showPaused(false)
    }

    /// A paused Zivlet shows a paused symbol in the menu bar.
    func showPaused(_ paused: Bool) {
        let symbol = paused ? "pause.circle" : "circle.hexagongrid"
        item.button?.image = NSImage(
            systemSymbolName: symbol, accessibilityDescription: paused ? "Zivlet, paused" : "Zivlet")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let entries = MenuModel.make(state: state())
        entries.forEach { menu.addItem(makeItem($0)) }
        #if DEBUG
            let quitIndex = menu.items.count - 1
            menu.insertItem(demoItem(), at: quitIndex)
        #endif
    }

    private func makeItem(_ entry: MenuEntry) -> NSMenuItem {
        if entry.isSeparator { return .separator() }
        let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: entry.keyEquivalent)
        item.isEnabled = entry.isEnabled
        item.subtitle = entry.subtitle
        if let action = entry.action {
            item.action = #selector(choose(_:))
            item.target = self
            item.representedObject = ActionBox(action)
        }
        if !entry.children.isEmpty {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            entry.children.forEach { submenu.addItem(makeItem($0)) }
            item.submenu = submenu
        }
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        perform(box.action)
    }

    #if DEBUG
        private func demoItem() -> NSMenuItem {
            let submenu = NSMenu()
            for mode in WheelMode.allCases {
                let entry = NSMenuItem(
                    title: mode.rawValue.capitalized, action: #selector(showDemo(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = mode.rawValue
                submenu.addItem(entry)
            }
            submenu.addItem(.separator())
            let hide = NSMenuItem(title: "Hide wheel", action: #selector(hideDemo), keyEquivalent: "")
            hide.target = self
            submenu.addItem(hide)
            let parent = NSMenuItem(title: "Show wheel (demo)", action: nil, keyEquivalent: "")
            parent.submenu = submenu
            return parent
        }

        @objc private func showDemo(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let mode = WheelMode(rawValue: raw) else { return }
            wheel?.showDemo(.sample(mode))
        }

        @objc private func hideDemo() { wheel?.hide() }
    #endif
}

/// `representedObject` needs an object.
private final class ActionBox {
    let action: MenuAction
    init(_ action: MenuAction) { self.action = action }
}
