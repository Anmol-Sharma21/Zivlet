import AppKit
import Testing
import ZivletCore
import ZivletTrigger

@testable import ZivletTriggerHost

@Suite("Trigger host: OS signals → TriggerMachine → effects (P0-40, 03a §1.1–1.4)")
struct TriggerHostTests {
    @Test func startListensForMouseDownOnlyWithNoTimers() {
        let rig = HostRig()
        #expect(rig.scheduler.plans == [SamplingPlan(events: [.mouseDown])])
        #expect(HostRig(flags: true).scheduler.current?.events == [.mouseDown, .flagsChanged])
    }

    @Test func pressedAddsDragMonitorsAndTheWatchdog() {
        let rig = HostRig()
        rig.event(.mouseDown, at: 0, down: true, count: 5)
        #expect(rig.scheduler.current == SamplingPlan(events: [.mouseDown, .mouseDragged, .mouseUp], watchdog: true))
        rig.event(.mouseDragged, at: 10)
        #expect(rig.scheduler.current == SamplingPlan(events: [.mouseDown, .mouseUp], sampling: true))
    }

    @Test func fileDragProbesOnceAndATapShowsTheWheelAtThePointer() async {
        let rig = HostRig()
        await rig.startFileDrag()
        #expect(rig.probed == [6])
        rig.input.location = Point2D(x: 300, y: 200)
        rig.event(.frame, at: 70, mods: .shift)
        #expect(rig.wheelEffects == [.show(.convert, at: Point2D(x: 300, y: 200))])
        #expect(
            rig.scheduler.current == SamplingPlan(events: [.mouseDown, .mouseUp], sampling: true, escapeHotkey: true))
    }

    @Test func aShowBeginsTheTriggerToFrameSignpost() async {
        let signpost = TriggerFrameSignpost()
        let rig = HostRig(signpost: signpost)
        await rig.startFileDrag()
        #expect(!signpost.isPending)
        rig.event(.frame, at: 70, mods: .shift)
        #expect(signpost.isPending)
        #expect(signpost.end() && !signpost.isPending && !signpost.end())
    }

    @Test func theHostKeepsATraceOfStateChangesForDiagnostics() async {
        let rig = HostRig()
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .shift)
        #expect(rig.host.trace.entries.map(\.to) == ["pressed", "detecting", "live", "wheel"])
        #expect(rig.host.trace.entries.last?.uptime == .milliseconds(70))
    }

    @Test func fileTypesAreReadOncePerChangeCountAndNeverWhileIdle() async {
        let rig = HostRig()
        rig.event(.frame, at: 0, count: 9)
        #expect(rig.input.typeReads == 0)
        await rig.startFileDrag()
        rig.event(.frame, at: 30)
        rig.event(.frame, at: 40)
        #expect(rig.input.typeReads == 1)
    }

    @Test func nonFileDragGoesPassiveWithOnlyTheWatchdog() {
        let rig = HostRig()
        rig.input.fileTypesPresent = false
        rig.event(.mouseDown, at: 0, down: true, count: 5)
        rig.event(.mouseDragged, at: 10)
        rig.event(.frame, at: 18, count: 6)
        #expect(rig.scheduler.current == SamplingPlan(events: [.mouseDown, .mouseUp], watchdog: true))
        rig.event(.frame, at: 500, down: false)
        #expect(rig.scheduler.current == SamplingPlan(events: [.mouseDown]))
        #expect(rig.probed.isEmpty && rig.wheelEffects.isEmpty)
    }

    @Test func eventSourceDecidesTheButtonForMouseEvents() {
        let rig = HostRig()
        rig.event(.mouseDown, at: 0, down: false, count: 1)
        #expect(rig.host.machine.state == .pressed(snapshot: 1, held: []))
        rig.event(.mouseUp, at: 5, down: true)
        #expect(rig.host.machine.state == .idle)
    }

    @Test func heldModifierIsIgnoredUntilPressedAgain() async {
        let rig = HostRig()
        await rig.startFileDrag(mods: .command)
        rig.event(.frame, at: 70)
        #expect(rig.wheelEffects.isEmpty)
        rig.event(.frame, at: 80, mods: [])
        rig.event(.frame, at: 90, mods: .command)
        #expect(rig.wheelEffects == [.show(.tools, at: rig.input.location)])
    }

    @Test func releaseOutsideHidesAndReturnsToIdle() async {
        let rig = HostRig()
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .control)
        rig.event(.mouseUp, at: 90, down: false, inside: false)
        #expect(rig.wheelEffects.last == .hide(.buttonUp))
        #expect(rig.scheduler.current == SamplingPlan(events: [.mouseDown]))
    }

    @Test func dropInsideWaitsForDropHandled() async {
        let rig = HostRig()
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .shift)
        rig.event(.mouseUp, at: 90, down: false, inside: true)
        #expect(rig.wheelEffects.count == 1)
        rig.scheduler.send(.dropHandled)
        #expect(rig.wheelEffects.last == .hide(.dropped))
        #expect(rig.host.machine.state == .idle)
    }

    /// Button up inside the wheel with no drop callback: the 150 ms linger ends the wheel from frame samples.
    @Test func releaseInsideWithoutADropExpiresAfterTheReleaseTimeout() async {
        let rig = HostRig()
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .shift)
        rig.event(.mouseUp, at: 90, down: false, inside: true)
        rig.event(.frame, at: 200, down: false, inside: true)
        #expect(rig.wheelEffects.count == 1)
        rig.event(.frame, at: 240, down: false, inside: true)
        #expect(rig.wheelEffects.last == .hide(.lingerExpired))
        #expect(rig.host.machine.state == .idle && rig.scheduler.current == SamplingPlan(events: [.mouseDown]))
    }

    @Test func monitoredEventsReportTheirSampleSource() {
        let sources = MonitoredEvent.allCases.map(\.source)
        #expect(sources == [.mouseDown, .mouseDragged, .mouseUp, .flagsChanged])
    }

    @Test func escapeAndSpaceChangeHideTheWheel() async {
        let rig = HostRig()
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .shift)
        rig.scheduler.send(.escape)
        #expect(rig.wheelEffects.last == .hide(.escape))
        rig.event(.frame, at: 80, mods: [])
        rig.event(.frame, at: 90, mods: .shift)
        rig.scheduler.send(.spaceChanged)
        #expect(rig.wheelEffects.last == .hide(.spaceChanged))
    }

    @Test func switchAndRejectAreForwarded() async {
        let rig = HostRig(summary: DragSummary(itemCount: 1, acceptedModes: [.convert, .actions]))
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .shift)
        rig.event(.frame, at: 80, mods: .control)
        rig.event(.frame, at: 90, mods: .command)
        #expect(rig.wheelEffects.dropFirst() == [.switchTo(.actions), .reject(.tools, .noItemsForMode)])
    }

    @Test func aLateProbeAfterTheDragEndedChangesNothing() async {
        let rig = HostRig()
        rig.event(.mouseDown, at: 0, down: true, count: 5)
        rig.event(.mouseDragged, at: 10)
        rig.event(.frame, at: 18, count: 6)
        rig.event(.mouseUp, at: 20, down: false)
        await rig.host.probeTask?.value
        #expect(rig.host.machine.state == .idle && rig.wheelEffects.isEmpty)
    }

    @Test func newBindingsApplyFromTheNextEdge() async throws {
        let rig = HostRig()
        let swapped = try TriggerBindings(convert: .option, tools: .command, actions: .control)
        rig.host.update(config: TriggerConfig(bindings: swapped))
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .option)
        #expect(rig.wheelEffects == [.show(.convert, at: rig.input.location)])
    }

    @Test func stopTurnsEverythingOff() async {
        let rig = HostRig()
        await rig.startFileDrag()
        rig.host.stop()
        #expect(rig.scheduler.current == SamplingPlan(events: []))
        #expect(rig.host.machine.state == .idle)
    }

    @Test func appKitFlagsMapToTheFourTriggerModifiers() {
        let flags: NSEvent.ModifierFlags = [.shift, .command, .capsLock, .function, .numericPad]
        #expect(ModifierMask(flags) == [.shift, .command])
        #expect(ModifierMask(NSEvent.ModifierFlags([.control, .option])) == [.control, .option])
        #expect(ModifierMask(NSEvent.ModifierFlags()) == [])
    }
}
