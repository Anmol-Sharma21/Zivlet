import ZivletCore

// T10–T18: wheel visible, then the release window.
extension TriggerMachine {
    func wheel(_ wheel: TriggerState.Wheel, _ event: TriggerEvent) -> TriggerStep {
        switch event {
        case .sample(let s): wheelSample(wheel, s)
        case .escape: backToLive(wheel, hide: .escape)  // T17
        case .spaceChanged: backToLive(wheel, hide: .spaceChanged)  // T18
        default: stay()
        }
    }

    func releasing(_ mode: WheelMode, deadline: Duration, _ event: TriggerEvent) -> TriggerStep {
        switch event {
        case .dropHandled: toIdle([.hide(.dropped)])  // T16
        case .escape: toIdle([.hide(.escape)])  // T17 (button up)
        case .sample(let s) where s.uptime >= deadline: toIdle([.hide(.lingerExpired)])
        default: stay()
        }
    }

    private func wheelSample(_ wheel: TriggerState.Wheel, _ s: InputSample) -> TriggerStep {
        guard s.primaryButtonDown else {
            guard s.pointerInsideWheel else { return toIdle([.hide(.buttonUp)]) }  // T14
            return go(.releasing(mode: wheel.mode, deadline: s.uptime + config.releaseTimeout))  // T15
        }
        let next = wheel.with(previous: s.modifiers)
        guard Self.isEdge(s.modifiers, previous: wheel.previous),
            let mode = config.bindings.mode(matching: s.modifiers)
        else { return go(.wheel(next)) }  // T13
        if mode == wheel.mode {
            return config.retapClosesWheel
                ? backToLive(next, hide: .sameModifierRetap)  // T10
                : go(.wheel(next))
        }
        guard wheel.summary.acceptedModes.contains(mode) else {
            return go(.wheel(next), [.reject(mode, .noItemsForMode)])  // T12
        }
        return go(.wheel(wheel.with(mode: mode, previous: s.modifiers)), [.switchTo(mode)])  // T11
    }

    /// Back to `live` with the summary kept; the debounce does not apply again.
    private func backToLive(_ wheel: TriggerState.Wheel, hide: HideReason) -> TriggerStep {
        let start = Duration.zero - config.edgeDebounce
        let live = TriggerState.Live(
            changeCount: wheel.changeCount, summary: wheel.summary, previous: wheel.previous,
            liveStart: start, pendingEdge: false, queued: nil, location: wheel.anchor)
        return go(.live(live), [.hide(hide)])
    }
}
