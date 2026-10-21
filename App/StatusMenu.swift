import AppKit
import ZivletCore
import ZivletTrigger
import ZivletWheel

/// Status item and menu (14 §3.1). M2: catalog counts, the bindings line, a DEBUG demo submenu, Quit.
final class StatusMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var wheel: WheelController?

    init(bindings: TriggerBindings, wheel: WheelController) {
        self.wheel = wheel
        super.init()
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: "Zivlet")
        item.menu = makeMenu(bindings)
    }

    private func makeMenu(_ bindings: TriggerBindings) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(Self.info(StatusSummary.text))
        menu.addItem(Self.info(bindings.menuSummary))
        #if DEBUG
            menu.addItem(.separator())
            menu.addItem(demoItem())
        #endif
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit Zivlet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private static func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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

enum StatusSummary {
    static var text: String {
        "\(ConversionCatalog.standard.pairs.count) conversions · \(ToolID.allCases.count) tools"
    }
}
