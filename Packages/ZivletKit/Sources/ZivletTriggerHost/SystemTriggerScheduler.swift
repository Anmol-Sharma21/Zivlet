import AppKit
import ZivletTrigger
import os

/// Applies a `SamplingPlan` with real AppKit facilities: global + local `NSEvent` monitors (no permission needed for
/// mouse events, 14 §1.2 B), the frame sampler, a 2 Hz watchdog timer, the Esc hot key, and the Space-change
/// notification. Every callback arrives on the main actor and is forwarded as a `TriggerSignal`.
public final class SystemTriggerScheduler: TriggerScheduling {
    public var onSignal: ((TriggerSignal) -> Void)?

    let escapeHotkey = EscapeHotkey()
    private let sampler = FrameSampler()
    private let watchdogInterval: Duration
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "trigger")
    private var monitors: [MonitoredEvent: [Any]] = [:]
    private var watchdog: Timer?
    private var spaceObserver: (any NSObjectProtocol)?

    public init(watchdogInterval: Duration = .milliseconds(500)) {
        self.watchdogInterval = watchdogInterval
        sampler.onFrame = { [weak self] in self?.emit(.event(.frame)) }
        escapeHotkey.onPress = { [weak self] in self?.emit(.escape) }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.emit(.spaceChanged) } }
    }

    isolated deinit {
        apply(.off)
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    var installedEvents: Set<MonitoredEvent> { Set(monitors.keys) }
    var escapeRegistered: Bool { escapeHotkey.isRegistered }

    public func apply(_ plan: SamplingPlan) {
        updateMonitors(plan.events)
        if plan.sampling { sampler.start(on: FrameSampler.screenUnderPointer()) } else { sampler.stop() }
        setWatchdog(plan.watchdog)
        setEscape(plan.escapeHotkey)
    }

    private func emit(_ signal: TriggerSignal) { onSignal?(signal) }

    private func updateMonitors(_ wanted: Set<MonitoredEvent>) {
        for event in installedEvents.subtracting(wanted) {
            monitors[event]?.forEach(NSEvent.removeMonitor)
            monitors[event] = nil
        }
        for event in wanted.subtracting(installedEvents) { monitors[event] = install(event) }
    }

    /// Global monitors see other apps' events; local monitors see drags that start in our own windows (14 §1.4).
    private func install(_ event: MonitoredEvent) -> [Any] {
        let mask = Self.mask(for: event)
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit(.event(event.source)) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] nsEvent in
            MainActor.assumeIsolated { self?.emit(.event(event.source)) }
            return nsEvent
        }
        return [global, local].compactMap { $0 }
    }

    private func setWatchdog(_ on: Bool) {
        guard on != (watchdog != nil) else { return }
        watchdog?.invalidate()
        watchdog = nil
        guard on else { return }
        let timer = Timer(timeInterval: watchdogInterval.timeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit(.event(.frame)) }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func setEscape(_ on: Bool) {
        guard on != escapeHotkey.isRegistered else { return }
        guard on else { return escapeHotkey.unregister() }
        if !escapeHotkey.register() { logger.error("Esc hot key refused; re-tap, hub drop and release still cancel") }
    }

    private static func mask(for event: MonitoredEvent) -> NSEvent.EventTypeMask {
        switch event {
        case .mouseDown: .leftMouseDown
        case .mouseDragged: .leftMouseDragged
        case .mouseUp: .leftMouseUp
        case .flagsChanged: .flagsChanged
        }
    }
}
