import AppKit
import SwiftUI

/// The Settings window (14 §3.2): a toolbar tab view with one SwiftUI form per pane.
public final class SettingsWindowController: NSWindowController {
    private let tabs = NSTabViewController()

    public init(model: SettingsModel) {
        tabs.tabStyle = .toolbar
        for pane in SettingsPane.allCases {
            let hosting = NSHostingController(rootView: pane.view(model: model))
            hosting.sizingOptions = .preferredContentSize
            hosting.title = pane.title
            let item = NSTabViewItem(viewController: hosting)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = SettingsPane.general.title
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Brings the window forward on `pane`; Zivlet has no Dock icon, so it activates itself first.
    public func show(_ pane: SettingsPane = .general) {
        if let index = SettingsPane.allCases.firstIndex(of: pane) { tabs.selectedTabViewItemIndex = index }
        window?.title = pane.title
        NSApplication.shared.activate()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
