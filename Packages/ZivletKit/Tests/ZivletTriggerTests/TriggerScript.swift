import ZivletCore

@testable import ZivletTrigger

/// Test DSL: builds events and folds them through the machine without mutation of shared state.
enum T {
    static let here = Point2D(x: 100, y: 200)
    static let everyMode = DragSummary(itemCount: 1, acceptedModes: Set(WheelMode.allCases))

    static func sample(
        _ ms: Int, _ source: SampleSource = .frame, mods: ModifierMask = [], down: Bool = true,
        cc: Int = 1, files: Bool = true, inside: Bool = false
    ) -> TriggerEvent {
        .sample(
            InputSample(
                uptime: .milliseconds(ms), source: source, modifiers: mods, primaryButtonDown: down,
                dragChangeCount: cc, dragHasFileTypes: files, location: here, pointerInsideWheel: inside))
    }

    /// mouse-down (cc 0) → first drag event → frame where the count moved with file types → payload.
    static func fileDrag(held: ModifierMask = [], summary: DragSummary = everyMode) -> [TriggerEvent] {
        [
            sample(0, .mouseDown, mods: held, cc: 0, files: false),
            sample(10, .mouseDragged, mods: held, cc: 0, files: false),
            sample(18, mods: held, cc: 1),
            .payload(changeCount: 1, summary: summary),
        ]
    }

    /// A tap: key down then key up, both after the 40 ms debounce (drag went live at 18 ms).
    static func tap(_ mods: ModifierMask, at ms: Int) -> [TriggerEvent] {
        [sample(ms, .flagsChanged, mods: mods), sample(ms + 30, .flagsChanged)]
    }

    struct Run {
        let machine: TriggerMachine
        let effects: [TriggerEffect]
    }

    static func run(_ events: [TriggerEvent], config: TriggerConfig = TriggerConfig()) -> Run {
        events.reduce(Run(machine: TriggerMachine(config: config), effects: [])) { acc, event in
            let step = acc.machine.step(event)
            return Run(machine: step.next, effects: acc.effects + step.effects)
        }
    }
}
