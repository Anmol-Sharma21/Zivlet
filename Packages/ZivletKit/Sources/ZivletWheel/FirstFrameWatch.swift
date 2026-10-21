import AppKit
import QuartzCore

/// Calls `onFrame` once, from the first display-link callback of `view`'s screen after the wheel is ordered in, then
/// stops (the end of the `trigger→frame` signpost). Without a view or screen it calls at once.
final class FirstFrameWatch: NSObject {
    private var link: CADisplayLink?
    private var onFrame: (() -> Void)?

    init(view: NSView?, onFrame: @escaping () -> Void) {
        self.onFrame = onFrame
        super.init()
        guard let view, view.window?.screen != nil else {
            fire()
            return
        }
        let link = view.displayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func frame(_ link: CADisplayLink) { fire() }

    /// Stops without calling (the wheel was hidden or shown again first).
    func cancel() {
        link?.invalidate()
        link = nil
        onFrame = nil
    }

    private func fire() {
        let callback = onFrame
        cancel()
        callback?()
    }
}
