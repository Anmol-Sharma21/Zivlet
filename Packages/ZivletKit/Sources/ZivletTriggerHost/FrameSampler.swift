import AppKit
import QuartzCore

/// Display-rate ticks while a drag is live (14 §1.3 step 2): `NSScreen.displayLink` on the screen under the pointer
/// (60–120 Hz). Without a screen it falls back to a main-queue timer.
final class FrameSampler: NSObject {
    var onFrame: () -> Void = {}
    private let fallbackInterval: Duration
    private var link: CADisplayLink?
    private var timer: Timer?

    init(fallbackInterval: Duration = .milliseconds(16)) {
        self.fallbackInterval = fallbackInterval
    }

    var isRunning: Bool { link != nil || timer != nil }

    func start(on screen: NSScreen?) {
        guard !isRunning else { return }
        guard let screen else { return startTimer() }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        timer?.invalidate()
        timer = nil
    }

    /// The screen whose frame holds the pointer, else the main screen.
    static func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    @objc private func tick(_ link: CADisplayLink) { onFrame() }

    private func startTimer() {
        let timer = Timer(timeInterval: fallbackInterval.timeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

extension Duration {
    /// Seconds as `TimeInterval` for `Timer`.
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
