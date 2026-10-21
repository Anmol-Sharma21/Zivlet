/// Hover intent and grace (design/19 §4.2, §4.4).
extension IslandMachine {
    mutating func pointerEntered(now: Duration, into effects: inout EffectList) {
        guard surface != .hidden, !isSuppressed else { return }
        switch hover {
        case .inside, .intent: return
        case .leaving:
            hover = .inside
            effects.deadline = .cancelDeadline
        case .outside:
            if surface == hoverSurface, !isPinned {
                hover = .inside
            } else {
                let until = now + Timing.intent
                hover = .intent(until: until)
                effects.deadline = .schedule(until)
            }
        }
    }

    mutating func pointerExited(now: Duration, into effects: inout EffectList) {
        switch hover {
        case .outside, .leaving: return
        case .intent:
            hover = .outside
            effects.deadline = .cancelDeadline
        case .inside:
            guard isOpenedBeyondRest else {
                hover = .outside
                return
            }
            startGrace(now: now, into: &effects)
        }
    }

    mutating func tick(now: Duration, into effects: inout EffectList) {
        switch hover {
        case .intent(let until) where now >= until:
            hover = .inside
            isPinned = false  // the pointer has entered: from now on its leaving collapses the card
            if surface != hoverSurface { show(hoverSurface, into: &effects) }
        case .leaving(let until) where now >= until:
            hover = .outside
            guard !isAccessibilityFocused, !isDragging, !isPinned else { return }
            settle(into: &effects)
        default:
            return
        }
    }

    mutating func startGrace(now: Duration, into effects: inout EffectList) {
        let until = now + Timing.grace
        hover = .leaving(until: until)
        effects.deadline = .schedule(until)
    }

    /// Back to the resting surface, or hidden when the client withdrew while something held the island.
    mutating func settle(into effects: inout EffectList) {
        if resting == .hidden {
            hide(into: &effects)
        } else if surface != resting {
            show(resting, into: &effects)
        }
    }
}
