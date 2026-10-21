import ZivletCore
import ZivletTrigger

/// The AppKit-side driver of the pure `TriggerMachine` (03a §1.1): turns OS signals into `InputSample`s, steps the
/// machine and executes its effects. Monitor, sampler and timer effects become a `SamplingPlan`; wheel effects go
/// to `onWheelEffect`; `probePayload` runs the injected probe and feeds the result back as `.payload`.
public final class TriggerHost {
    public typealias PayloadProbe = @MainActor (Int) async -> DragSummary

    public private(set) var machine: TriggerMachine
    public private(set) var plan = SamplingPlan.off
    /// The running payload probe; tests await it.
    public private(set) var probeTask: Task<Void, Never>?
    /// The last 50 state changes, for Copy Diagnostics (P1-48).
    public private(set) var trace = TriggerTrace()
    public var onWheelEffect: (TriggerEffect) -> Void = { _ in }

    private let reader: any InputReading
    private let scheduler: any TriggerScheduling
    private let probe: PayloadProbe
    private let baseEvents: Set<MonitoredEvent>
    private let frameSignpost: TriggerFrameSignpost
    private var dragEvents: Set<MonitoredEvent> = []
    private var sampling = false
    private var fileTypes: (changeCount: Int, present: Bool)?

    public init(
        config: TriggerConfig = TriggerConfig(), reader: any InputReading, scheduler: any TriggerScheduling,
        listensToFlagsChanged: Bool = false, frameSignpost: TriggerFrameSignpost = .shared,
        probe: @escaping PayloadProbe
    ) {
        machine = TriggerMachine(config: config)
        self.frameSignpost = frameSignpost
        self.reader = reader
        self.scheduler = scheduler
        self.probe = probe
        baseEvents = listensToFlagsChanged ? [.mouseDown, .flagsChanged] : [.mouseDown]
        scheduler.onSignal = { [weak self] in self?.receive($0) }
    }

    /// Idle: only the mouse-down monitors, no timers (03a §1.5: zero idle wakeups).
    public func start() { applyPlanIfChanged() }

    public func stop() {
        probeTask?.cancel()
        machine = TriggerMachine(config: machine.config)
        dragEvents = []
        sampling = false
        plan = .off
        scheduler.apply(.off)
    }

    /// T19: new bindings apply from the next edge.
    public func update(config: TriggerConfig) { machine = machine.with(config: config) }

    public func receive(_ signal: TriggerSignal) {
        switch signal {
        case .event(let source): step(.sample(sample(source)))
        case .escape: step(.escape)
        case .spaceChanged: step(.spaceChanged)
        case .dropHandled: step(.dropHandled)
        }
    }

    private func step(_ event: TriggerEvent) {
        let result = machine.step(event)
        if let entry = TriggerTrace.entry(event: event, from: machine.state, step: result, uptime: reader.uptime) {
            trace = trace.recording(entry)
        }
        machine = result.next
        result.effects.forEach(execute)
        applyPlanIfChanged()
    }

    private func execute(_ effect: TriggerEffect) {
        switch effect {
        case .installDragMonitors: dragEvents = [.mouseDragged, .mouseUp]
        case .removeDraggedMonitor: dragEvents.remove(.mouseDragged)
        case .removeDragMonitors: dragEvents = []
        case .startSampler: sampling = true
        case .stopSampler: sampling = false
        case .probePayload(let count): startProbe(count)
        case .show:
            frameSignpost.begin()  // trigger→frame; the wheel ends it at its first frame
            onWheelEffect(effect)
        case .switchTo, .reject, .hide: onWheelEffect(effect)
        }
    }

    private func startProbe(_ count: Int) {
        probeTask?.cancel()
        probeTask = Task { [weak self, probe] in
            let summary = await probe(count)
            guard !Task.isCancelled else { return }
            self?.step(.payload(changeCount: count, summary: summary))
        }
    }

    private func sample(_ source: SampleSource) -> InputSample {
        let count = reader.dragChangeCount
        return InputSample(
            uptime: reader.uptime, source: source, modifiers: reader.modifiers,
            primaryButtonDown: buttonDown(for: source), dragChangeCount: count,
            dragHasFileTypes: hasFileTypes(count), location: reader.location,
            pointerInsideWheel: reader.pointerInsideWheel)
    }

    /// A mouse event states the button itself; `pressedMouseButtons` can lag behind a quick click.
    private func buttonDown(for source: SampleSource) -> Bool {
        switch source {
        case .mouseDown, .mouseDragged: true
        case .mouseUp: false
        case .frame, .flagsChanged: reader.primaryButtonDown
        }
    }

    /// Types-only check, only while detecting and once per change count (03a §1.2).
    private func hasFileTypes(_ count: Int) -> Bool {
        guard case .detecting(let snapshot, _, _) = machine.state, count != snapshot else { return false }
        if let cached = fileTypes, cached.changeCount == count { return cached.present }
        let present = reader.dragHasFileTypes()
        fileTypes = (count, present)
        return present
    }

    private func applyPlanIfChanged() {
        let next = SamplingPlan(
            events: baseEvents.union(dragEvents), sampling: sampling, watchdog: needsWatchdog,
            escapeHotkey: wheelVisible)
        guard next != plan else { return }
        plan = next
        scheduler.apply(next)
    }

    private var needsWatchdog: Bool {
        switch machine.state {
        case .pressed, .passive: true
        default: false
        }
    }

    private var wheelVisible: Bool {
        switch machine.state {
        case .wheel, .releasing: true
        default: false
        }
    }
}
