/// Accessibility focus, drags from the island, the menu command, the keyboard and the wheel (design/19 §4.2, §5.1,
/// §5.4, D-N12, D-N13).
extension IslandMachine {
    /// Focus opens the card at once (no intent delay) and holds it; while the wheel shows it only holds.
    mutating func accessibilityFocused(into effects: inout EffectList) {
        guard surface != .hidden, !isAccessibilityFocused else { return }
        isAccessibilityFocused = true
        guard !isSuppressed, surface != hoverSurface else { return }
        show(hoverSurface, into: &effects)
        if case .intent = hover {
            hover = .inside
            effects.deadline = .cancelDeadline
        }
    }

    /// Focus leaving acts as the pointer leaving: grace, then the resting surface.
    mutating func accessibilityUnfocused(now: Duration, into effects: inout EffectList) {
        guard isAccessibilityFocused else { return }
        isAccessibilityFocused = false
        guard isOpenedBeyondRest, hover == .outside, !isDragging, !isPinned else { return }
        startGrace(now: now, into: &effects)
    }

    /// A drag that left the island ends: hidden if the client withdrew meanwhile, else grace unless the pointer is in.
    mutating func dragEnded(now: Duration, into effects: inout EffectList) {
        guard isDragging else { return }
        isDragging = false
        if request == nil {
            hide(into: &effects)
        } else if isOpenedBeyondRest, hover == .outside, !isAccessibilityFocused, !isPinned {
            startGrace(now: now, into: &effects)
        }
    }

    /// The status-menu command or the accessibility action: open, and take the keyboard so Tab and Escape work.
    mutating func expandRequested(into effects: inout EffectList) {
        guard surface != .hidden else { return }
        isKeyed = true
        if hover != .inside, !isLeaving { isPinned = true }
        if surface != hoverSurface { show(hoverSurface, into: &effects) }
        effects.key = .becomeKey
    }

    /// A click into the card's text lets the panel become key (D-M4-16).
    mutating func clicked(into effects: inout EffectList) {
        guard surface != .hidden, !isKeyed else { return }
        isKeyed = true
        effects.key = .becomeKeyAllowed
    }

    /// Only after a click or the menu command; a closable card also asks its client to close.
    mutating func escape(into effects: inout EffectList) {
        guard isKeyed, surface == .expanded, let request else { return }
        isKeyed = false
        isPinned = false
        if deadline != nil { effects.deadline = .cancelDeadline }
        hover = .outside
        if surface != resting { show(resting, into: &effects) }
        effects.key = .resignKey
        if request.closable { effects.close = .closeRequested(request.client) }
    }

    /// The wheel wins (W-8): a card opened by hover or focus goes back to rest; a pinned or dragged one stays.
    mutating func wheelShown(into effects: inout EffectList) {
        guard !isSuppressed else { return }
        isSuppressed = true
        guard surface != .hidden, !isPinned, !isDragging else { return }
        if deadline != nil { effects.deadline = .cancelDeadline }
        hover = .outside
        if isOpenedBeyondRest { show(resting, into: &effects) }
    }

    private var isLeaving: Bool {
        if case .leaving = hover { return true }
        return false
    }
}
