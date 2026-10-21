import ZivletCore
import ZivletTrigger

@testable import ZivletTriggerHost

/// Scriptable OS reads. Tests set fields, then send a signal; the host reads them while building the sample.
final class FakeInput: InputReading {
    var uptime: Duration = .zero
    var modifiers: ModifierMask = []
    var primaryButtonDown = false
    var dragChangeCount = 0
    var location = Point2D(x: 640, y: 400)
    var pointerInsideWheel = false
    var fileTypesPresent = true
    private(set) var typeReads = 0

    func dragHasFileTypes() -> Bool {
        typeReads += 1
        return fileTypesPresent
    }
}

/// Records every plan the host applies; `send` plays the OS layer calling back into the host.
final class FakeScheduler: TriggerScheduling {
    private(set) var plans: [SamplingPlan] = []
    var onSignal: ((TriggerSignal) -> Void)?

    var current: SamplingPlan? { plans.last }
    func apply(_ plan: SamplingPlan) { plans.append(plan) }
    func send(_ signal: TriggerSignal) { onSignal?(signal) }
}

/// Change counts the payload probe was asked for.
final class ProbeLog {
    private(set) var counts: [Int] = []
    func record(_ count: Int) { counts.append(count) }
}

/// Builds a host wired to fakes and collects the wheel effects it forwards.
final class HostRig {
    let input = FakeInput()
    let scheduler = FakeScheduler()
    let probes = ProbeLog()
    private(set) var wheelEffects: [TriggerEffect] = []
    let host: TriggerHost

    var probed: [Int] { probes.counts }

    init(
        config: TriggerConfig = TriggerConfig(), flags: Bool = false,
        summary: DragSummary = DragSummary(itemCount: 1, acceptedModes: Set(WheelMode.allCases))
    ) {
        host = TriggerHost(
            config: config, reader: input, scheduler: scheduler, listensToFlagsChanged: flags,
            probe: { [probes] count in
                probes.record(count)
                return summary
            })
        host.onWheelEffect = { [unowned self] in wheelEffects.append($0) }
        host.start()
    }

    /// Advances the clock, applies OS state, then delivers one event through the scheduler callback.
    func event(
        _ source: SampleSource, at ms: Int, mods: ModifierMask? = nil, down: Bool? = nil, count: Int? = nil,
        inside: Bool? = nil
    ) {
        input.uptime = .milliseconds(ms)
        if let mods { input.modifiers = mods }
        if let down { input.primaryButtonDown = down }
        if let count { input.dragChangeCount = count }
        if let inside { input.pointerInsideWheel = inside }
        scheduler.send(.event(source))
    }

    /// Mouse-down at 0 ms (count 5), first drag event at 10 ms, file types on the pasteboard at 18 ms, probe done.
    func startFileDrag(mods: ModifierMask = []) async {
        event(.mouseDown, at: 0, mods: mods, down: true, count: 5)
        event(.mouseDragged, at: 10)
        event(.frame, at: 18, count: 6)
        await host.probeTask?.value
    }
}
