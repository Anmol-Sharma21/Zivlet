import ZivletCore

/// Pure trigger state machine (03a §1.4). Transition numbers T1…T19 refer to that table.
public struct TriggerMachine: Sendable, Equatable {
    public let config: TriggerConfig
    public let state: TriggerState

    public init(config: TriggerConfig = TriggerConfig(), state: TriggerState = .idle) {
        self.config = config
        self.state = state
    }

    /// T19: new bindings apply from the next edge; state is kept.
    public func with(config: TriggerConfig) -> TriggerMachine { TriggerMachine(config: config, state: state) }

    public func step(_ event: TriggerEvent) -> TriggerStep {
        switch (state, event) {
        case (.idle, .sample(let s)): idle(s)
        case (.pressed(let snap, let held), .sample(let s)): pressed(s, snap: snap, held: held)
        case (.detecting(let snap, let held, let deadline), .sample(let s)):
            detecting(s, snap: snap, held: held, deadline: deadline)
        case (.passive, .sample(let s)): s.primaryButtonDown ? stay() : toIdle()
        case (.live(let live), _): self.live(live, event)
        case (.wheel(let wheel), _): self.wheel(wheel, event)
        case (.releasing(let mode, let deadline), _): releasing(mode, deadline: deadline, event)
        default: stay()
        }
    }

    // MARK: helpers shared by the extensions

    func go(_ state: TriggerState, _ effects: [TriggerEffect] = []) -> TriggerStep {
        TriggerStep(next: TriggerMachine(config: config, state: state), effects: effects)
    }

    func stay(_ effects: [TriggerEffect] = []) -> TriggerStep { go(state, effects) }

    /// T3 / T14 / T16 tail: back to idle; the host keeps only its mouse-down monitor.
    func toIdle(_ leading: [TriggerEffect] = []) -> TriggerStep {
        go(.idle, leading + [.stopSampler, .removeDragMonitors])
    }

    static func isEdge(_ mods: ModifierMask, previous: ModifierMask) -> Bool {
        !mods.subtracting(previous).isEmpty
    }

    // MARK: T1, T2, T4, T5

    private func idle(_ s: InputSample) -> TriggerStep {
        guard s.source == .mouseDown, s.primaryButtonDown else { return stay() }
        return go(.pressed(snapshot: s.dragChangeCount, held: s.modifiers), [.installDragMonitors])
    }

    private func pressed(_ s: InputSample, snap: Int, held: ModifierMask) -> TriggerStep {
        guard s.primaryButtonDown else { return toIdle() }
        guard s.source == .mouseDragged else { return stay() }
        let deadline = s.uptime + config.detectionWindow
        return go(.detecting(snapshot: snap, held: held, deadline: deadline), [.removeDraggedMonitor, .startSampler])
    }

    private func detecting(_ s: InputSample, snap: Int, held: ModifierMask, deadline: Duration) -> TriggerStep {
        guard s.primaryButtonDown else { return toIdle() }
        if s.dragChangeCount != snap {
            guard s.dragHasFileTypes else { return go(.passive, [.stopSampler]) }
            let previous: ModifierMask = config.honorsModifierHeldAtDragStart ? [] : held
            let live = TriggerState.Live(
                changeCount: s.dragChangeCount, summary: nil, previous: previous,
                liveStart: s.uptime, pendingEdge: false, queued: nil, location: s.location)
            return go(.live(live), [.probePayload(changeCount: s.dragChangeCount)])
        }
        return s.uptime >= deadline ? go(.passive, [.stopSampler]) : stay()
    }
}
