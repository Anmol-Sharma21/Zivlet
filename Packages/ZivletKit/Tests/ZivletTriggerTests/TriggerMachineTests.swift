import Testing
import ZivletCore

@testable import ZivletTrigger

@Suite("TriggerMachine (P0-23, 03a §1.4)")
struct TriggerMachineTests {
    @Test func fileDragThenShiftTapShowsConvertWheelAtPointer() {
        let run = T.run(T.fileDrag() + T.tap(.shift, at: 100))
        #expect(
            run.effects == [
                .installDragMonitors, .removeDraggedMonitor, .startSampler,
                .probePayload(changeCount: 1), .show(.convert, at: T.here),
            ])
        #expect(run.machine.state.isWheel(.convert))
    }

    @Test func keyReleaseNeverChangesTheWheel() {
        let run = T.run(T.fileDrag() + [T.sample(100, mods: .shift), T.sample(130), T.sample(160)])
        #expect(run.effects.filter { $0.isWheelChange } == [.show(.convert, at: T.here)])
    }

    @Test func nonFileDragGoesPassiveAndNeverShows() {
        let events =
            [
                T.sample(0, .mouseDown, cc: 0, files: false), T.sample(10, .mouseDragged, cc: 0, files: false),
                T.sample(18, cc: 1, files: false),
            ] + T.tap(.shift, at: 100)
        let run = T.run(events)
        #expect(run.machine.state == .passive)
        #expect(!run.effects.contains { $0.isShow })
    }

    @Test func detectionWindowExpiresAfter300ms() {
        let events = [
            T.sample(0, .mouseDown, cc: 0), T.sample(10, .mouseDragged, cc: 0),
            T.sample(309, cc: 0), T.sample(310, cc: 0),
        ]
        let run = T.run(events)
        #expect(run.machine.state == .passive)
        #expect(run.effects.last == .stopSampler)
    }

    @Test func unboundChordIsIgnored() {
        let run = T.run(T.fileDrag() + T.tap([.shift, .command], at: 100))
        #expect(!run.effects.contains { $0.isShow })
    }

    @Test func modifierHeldBeforeDragIsIgnoredByDefault() {
        let run = T.run(T.fileDrag(held: .command) + [T.sample(60, mods: .command)])
        #expect(!run.effects.contains { $0.isShow })
    }

    @Test func heldModifierOpensWheelOnceReleasedAndPressedAgain() {
        let run = T.run(T.fileDrag(held: .command) + [T.sample(60), T.sample(70, mods: .command)])
        #expect(run.effects.last == .show(.tools, at: T.here))
    }

    @Test func modifierHeldBeforeDragOpensWheelWhenParityIsOn() {
        let config = TriggerConfig(honorsModifierHeldAtDragStart: true)
        let run = T.run(T.fileDrag(held: .command) + [T.sample(60, mods: .command)], config: config)
        #expect(run.effects.last == .show(.tools, at: T.here))
    }

    @Test func edgeBeforePayloadIsQueuedAndAppliedOnArrival() {
        let drag = Array(T.fileDrag().dropLast())  // payload not yet delivered
        let run = T.run(drag + [T.sample(70, mods: .control), .payload(changeCount: 1, summary: T.everyMode)])
        #expect(run.effects.last == .show(.actions, at: T.here))
    }

    @Test func edgeInsideDebounceFiresAtTheMarkWithCurrentSet() {
        let early = T.run(T.fileDrag() + [T.sample(25, mods: .shift)])  // 7 ms after live
        #expect(!early.effects.contains { $0.isShow })
        let atMark = T.run(T.fileDrag() + [T.sample(25, mods: .shift), T.sample(58, mods: [.shift, .command])])
        #expect(!atMark.effects.contains { $0.isShow }, "⇧⌘ at the mark is unbound")
        let resolved = T.run(T.fileDrag() + [T.sample(25, mods: .shift), T.sample(58, mods: .shift)])
        #expect(resolved.effects.last == .show(.convert, at: T.here))
    }

    @Test func otherBindingSwitchesInPlace() {
        let run = T.run(T.fileDrag() + T.tap(.shift, at: 100) + T.tap(.command, at: 200))
        #expect(run.effects.suffix(2) == [.show(.convert, at: T.here), .switchTo(.tools)])
        #expect(run.machine.state.isWheel(.tools))
    }

    @Test func switchToWheelThatRejectsItemsKeepsOldWheel() {
        let summary = DragSummary(itemCount: 1, acceptedModes: [.convert, .actions])
        let run = T.run(T.fileDrag(summary: summary) + T.tap(.shift, at: 100) + T.tap(.command, at: 200))
        #expect(run.effects.last == .reject(.tools, .noItemsForMode))
        #expect(run.machine.state.isWheel(.convert))
    }

    @Test func retapClosesAndAThirdTapReopens() {
        let closed = T.run(T.fileDrag() + T.tap(.shift, at: 100) + T.tap(.shift, at: 200))
        #expect(closed.effects.last == .hide(.sameModifierRetap))
        let reopened = T.run(T.fileDrag() + T.tap(.shift, at: 100) + T.tap(.shift, at: 200) + T.tap(.shift, at: 300))
        #expect(reopened.effects.last == .show(.convert, at: T.here))
    }

    @Test func releaseOutsideWheelHidesAtOnce() {
        let run = T.run(T.fileDrag() + T.tap(.shift, at: 100) + [T.sample(400, .mouseUp, down: false)])
        #expect(run.effects.suffix(3) == [.hide(.buttonUp), .stopSampler, .removeDragMonitors])
        #expect(run.machine.state == .idle)
    }

    @Test func releaseInsideWaitsForDropHandled() {
        let events =
            T.fileDrag() + T.tap(.shift, at: 100) + [
                T.sample(400, .mouseUp, down: false, inside: true),
                T.sample(450, down: false, inside: true), .dropHandled,
            ]
        let run = T.run(events)
        #expect(run.effects.suffix(3) == [.hide(.dropped), .stopSampler, .removeDragMonitors])
    }

    @Test(arguments: [(150, 549, 550), (300, 699, 700)])
    func releaseInsideTimesOut(timeoutMs: Int, before: Int, at: Int) {
        let config = TriggerConfig(releaseTimeout: .milliseconds(timeoutMs))
        let base = T.fileDrag() + T.tap(.shift, at: 100) + [T.sample(400, .mouseUp, down: false, inside: true)]
        let waiting = T.run(base + [T.sample(before, down: false)], config: config)
        #expect(waiting.machine.state == .releasing(mode: .convert, deadline: .milliseconds(400 + timeoutMs)))
        let expired = T.run(base + [T.sample(at, down: false)], config: config)
        #expect(expired.effects.suffix(3) == [.hide(.lingerExpired), .stopSampler, .removeDragMonitors])
    }

    @Test func escapeHidesButKeepsTheDragLive() {
        let run = T.run(T.fileDrag() + T.tap(.shift, at: 100) + [.escape])
        #expect(run.effects.last == .hide(.escape))
        #expect(run.machine.state.isLive)
        let again = T.run(T.fileDrag() + T.tap(.shift, at: 100) + [.escape] + T.tap(.command, at: 300))
        #expect(again.effects.last == .show(.tools, at: T.here))
    }

    @Test func escapeWhileReleasingGoesIdle() {
        let events =
            T.fileDrag() + T.tap(.shift, at: 100) + [T.sample(400, .mouseUp, down: false, inside: true), .escape]
        #expect(T.run(events).effects.suffix(3) == [.hide(.escape), .stopSampler, .removeDragMonitors])
    }

    @Test func spaceChangeHides() {
        let run = T.run(T.fileDrag() + T.tap(.shift, at: 100) + [.spaceChanged])
        #expect(run.effects.last == .hide(.spaceChanged))
    }

    @Test(arguments: [1, 2, 3])
    func buttonUpBeforeWheelReturnsToIdle(prefixLength: Int) {
        let events = Array(T.fileDrag().prefix(prefixLength)) + [T.sample(50, .mouseUp, down: false)]
        let run = T.run(events)
        #expect(run.machine.state == .idle)
        #expect(run.effects.suffix(2) == [.stopSampler, .removeDragMonitors])
    }

    @Test func staleOrUnexpectedEventsAreNoOps() {
        let idle = TriggerMachine()
        #expect(idle.step(.escape) == TriggerStep(next: idle, effects: []))
        #expect(idle.step(T.sample(5)) == TriggerStep(next: idle, effects: []))
        let live = T.run(Array(T.fileDrag().dropLast())).machine
        #expect(live.step(.payload(changeCount: 99, summary: T.everyMode)).next == live)
    }

    @Test func newBindingsApplyFromTheNextEdge() throws {
        let config = TriggerConfig(bindings: try TriggerBindings(convert: .option, tools: .command, actions: .control))
        let live = T.run(T.fileDrag()).machine.with(config: config)
        #expect(live.state.isLive)
        #expect(live.step(T.sample(100, mods: .option)).effects == [.show(.convert, at: T.here)])
    }
}

extension TriggerState {
    func isWheel(_ mode: WheelMode) -> Bool {
        if case .wheel(let w) = self { return w.mode == mode }
        return false
    }
    var isLive: Bool {
        if case .live = self { return true }
        return false
    }
}

extension TriggerEffect {
    var isShow: Bool {
        if case .show = self { return true }
        return false
    }
    var isWheelChange: Bool {
        switch self {
        case .show, .switchTo, .hide: true
        default: false
        }
    }
}
