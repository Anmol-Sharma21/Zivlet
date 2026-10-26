import AppKit

/// How the Drop Box panel leaves (G-M5b-10, 19c D-BL12): its opacity goes to 0 over `seconds`, then `completion`
/// runs (the controller orders it out). `cancel` stops a fade and makes the panel fully opaque again. Tests use an
/// instant or recording fader; the app animates with AppKit.
@MainActor
public protocol PanelFading {
    func fadeOut(_ panel: NSWindow, seconds: Double, completion: @escaping @MainActor @Sendable () -> Void)
    func cancel(_ panel: NSWindow)
}

/// `NSAnimationContext` on the window's alpha, eased out.
public struct SystemPanelFader: PanelFading {
    public init() {}

    public func fadeOut(_ panel: NSWindow, seconds: Double, completion: @escaping @MainActor @Sendable () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = seconds
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
    }

    public func cancel(_ panel: NSWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.alphaValue = 1
    }
}
