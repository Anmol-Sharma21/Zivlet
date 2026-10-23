import ZivletNotchCore

/// The expected surface and effects of each event (sent at t1, after every pending deadline) in each state, written
/// out from design/19 §4.2. Shown surfaces carry the 108 pt the host measured, except where a row says otherwise.
extension IslandMachineTableTests {
    typealias T = IslandMachineTableTests

    static let table: [State: [String: Row]] = [
        .hidden: hiddenRows, .collapsed: restingRows(.collapsed), .toast: restingRows(.toast),
        .hoverExpanded: hoverExpandedRows, .focusExpanded: focusExpandedRows, .dragHeld: dragHeldRows,
        .pinned: pinnedRows, .keyed: keyedRows, .keyedLeaving: keyedLeavingRows, .suppressed: suppressedRows,
    ]

    static var hiddenRows: [String: Row] {
        var rows = Dictionary(uniqueKeysWithValues: events.map { ($0.0, Row(surface: .hidden, effects: same)) })
        rows["request(toast)"] = Row(surface: .toast, effects: [show(.toast, 0)])
        rows["request(collapsed)"] = Row(surface: .collapsed, effects: [show(.collapsed, 0)])
        return rows
    }

    /// Collapsed and toast behave alike except for the requests.
    static func restingRows(_ resting: IslandSurface) -> [String: Row] {
        let other: IslandSurface = resting == .toast ? .collapsed : .toast
        return [
            "request(nil)": Row(surface: .hidden, effects: [.hide, .cancelDeadline]),
            "request(\(resting))": Row(surface: resting, effects: same),
            "request(\(other))": Row(surface: other, effects: [show(other)]),
            "contentHeightChanged": Row(surface: resting, effects: same),
            "pointerEntered": Row(surface: resting, effects: [.schedule(intent), .held(true)]),
            "pointerExited": Row(surface: resting, effects: same),
            "accessibilityFocused": Row(surface: .expanded, effects: [show(.expanded), .held(true)]),
            "accessibilityUnfocused": Row(surface: resting, effects: same),
            "dragBegan": Row(surface: resting, effects: [.held(true)]),
            "dragEnded": Row(surface: resting, effects: same),
            "expandRequested": Row(surface: .expanded, effects: [show(.expanded), .held(true), .becomeKey]),
            "tick": Row(surface: resting, effects: same),
            "clicked": Row(surface: resting, effects: [.held(true), .becomeKeyAllowed]),
            "resignedKey": Row(surface: resting, effects: same),
            "escape": Row(surface: resting, effects: same),
            "wheelShown": Row(surface: resting, effects: same),
            "wheelHidden": Row(surface: resting, effects: same),
            "reduceMotionChanged": Row(surface: resting, effects: same),
        ]
    }

    /// Shared by the expanded states: requests keep the card while it is held, a new height re-lays it out.
    static func expandedRows(_ overrides: [String: [IslandEffect]], surfaces: [String: IslandSurface] = [:])
        -> [String: Row]
    {
        var effects: [String: [IslandEffect]] = Dictionary(uniqueKeysWithValues: events.map { ($0.0, same) })
        effects["contentHeightChanged"] = [show(.expanded, 200)]
        effects["expandRequested"] = [.becomeKey]
        effects["clicked"] = [.becomeKeyAllowed]
        effects.merge(overrides) { _, new in new }
        return effects.reduce(into: [:]) { rows, entry in
            rows[entry.key] = Row(surface: surfaces[entry.key] ?? .expanded, effects: entry.value)
        }
    }

    static var hoverExpandedRows: [String: Row] {
        expandedRows(
            [
                "request(nil)": [.hide, .cancelDeadline, .held(false)],
                "pointerExited": [.schedule(grace), .held(false)],
                "wheelShown": [show(.collapsed), .held(false)],
            ], surfaces: ["request(nil)": .hidden, "wheelShown": .collapsed])
    }

    static var focusExpandedRows: [String: Row] {
        expandedRows(
            [
                "request(nil)": [.hide, .cancelDeadline, .held(false)],
                "accessibilityUnfocused": [.schedule(grace), .held(false)],
                "wheelShown": [show(.collapsed)],
            ], surfaces: ["request(nil)": .hidden, "wheelShown": .collapsed])
    }

    static var dragHeldRows: [String: Row] {
        expandedRows(["dragEnded": [.schedule(grace), .held(false)]])
    }

    /// Opened by the menu command: it has the keyboard, so it holds; giving the keyboard back releases the hold.
    static var pinnedRows: [String: Row] {
        expandedRows(
            [
                "request(nil)": [.hide, .cancelDeadline, .held(false), .resignKey],
                "pointerEntered": [.schedule(intent)],
                "clicked": same,
                "resignedKey": [.held(false)],
                "escape": [show(.collapsed), .held(false), .resignKey],
            ], surfaces: ["request(nil)": .hidden, "escape": .collapsed])
    }

    /// A click made the card key: the keyboard holds it past the pointer leaving, and goes back when it collapses.
    static var keyedRows: [String: Row] {
        expandedRows(
            [
                "request(nil)": [.hide, .cancelDeadline, .held(false), .resignKey],
                "pointerExited": [.schedule(grace)],
                "clicked": same,
                "escape": [show(.collapsed), .held(false), .resignKey],
                "wheelShown": [show(.collapsed), .held(false), .resignKey],
            ], surfaces: ["request(nil)": .hidden, "escape": .collapsed, "wheelShown": .collapsed])
    }

    /// Keyed, and the pointer has left: the grace runs; when it ends the card collapses and the keyboard goes back.
    static var keyedLeavingRows: [String: Row] {
        expandedRows(
            [
                "request(nil)": [.hide, .cancelDeadline, .held(false), .resignKey],
                "pointerEntered": [.cancelDeadline],
                "tick": [show(.collapsed), .held(false), .resignKey],
                "clicked": same,
                "resignedKey": [.held(false)],
                "escape": [show(.collapsed), .cancelDeadline, .held(false), .resignKey],
                "wheelShown": [show(.collapsed), .cancelDeadline, .held(false), .resignKey],
            ], surfaces: ["request(nil)": .hidden, "tick": .collapsed, "escape": .collapsed, "wheelShown": .collapsed])
    }

    static var suppressedRows: [String: Row] {
        var rows = restingRows(.collapsed)
        rows["pointerEntered"] = Row(surface: .collapsed, effects: same)
        rows["accessibilityFocused"] = Row(surface: .collapsed, effects: [.held(true)])
        return rows
    }
}
