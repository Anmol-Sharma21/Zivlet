import AppKit
import SwiftUI

/// The onboarding window (03b §8.2): 720 × 480, not resizable, centred.
public final class OnboardingWindowController: NSWindowController {
    public init(model: OnboardingModel) {
        let hosting = NSHostingController(rootView: OnboardingView(model: model))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Welcome to Zivlet"
        window.setContentSize(OnboardingView.size)
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public func show() {
        NSApplication.shared.activate()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
