import ZivletCore

// T3, T6–T9: file drag in progress, no wheel yet.
extension TriggerMachine {
    func live(_ live: TriggerState.Live, _ event: TriggerEvent) -> TriggerStep {
        switch event {
        case .sample(let s): liveSample(live, s)
        case .payload(let count, let summary) where count == live.changeCount: livePayload(live, summary)
        default: stay()
        }
    }

    private func liveSample(_ live: TriggerState.Live, _ s: InputSample) -> TriggerStep {
        guard s.primaryButtonDown else { return toIdle() }
        let pending = live.pendingEdge || Self.isEdge(s.modifiers, previous: live.previous)
        // Edges inside the debounce window are held and fire at the mark with the then-current set.
        guard pending, s.uptime - live.liveStart >= config.edgeDebounce else {
            return go(.live(live.observing(s, pendingEdge: pending)))
        }
        let next = live.observing(s, pendingEdge: false)
        guard let mode = config.bindings.mode(matching: s.modifiers) else { return go(.live(next)) }
        guard let summary = live.summary else { return go(.live(next.queueing(mode))) }  // T6
        return show(mode, live: next, summary: summary)  // T8 / T9
    }

    private func livePayload(_ live: TriggerState.Live, _ summary: DragSummary) -> TriggerStep {
        let next = live.receiving(summary)
        guard let mode = live.queued else { return go(.live(next)) }  // T7
        return show(mode, live: next, summary: summary)
    }

    /// T8 and T9 both show; a non-accepting wheel renders its empty-state pill and refuses drops.
    private func show(_ mode: WheelMode, live: TriggerState.Live, summary: DragSummary) -> TriggerStep {
        let wheel = TriggerState.Wheel(
            mode: mode, changeCount: live.changeCount, summary: summary,
            previous: live.previous, anchor: live.location)
        return go(.wheel(wheel), [.show(mode, at: live.location)])
    }
}
