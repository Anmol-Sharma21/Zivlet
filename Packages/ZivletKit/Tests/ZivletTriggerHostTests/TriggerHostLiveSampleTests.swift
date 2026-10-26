import Testing
import ZivletCore
import ZivletTrigger

@testable import ZivletTriggerHost

/// Collects what the host hands to the tray and shake hooks.
final class HookLog {
    private(set) var samples: [Duration] = []
    private(set) var dragEnds = 0

    init(_ host: TriggerHost) {
        host.onLiveSample = { [unowned self] in samples.append($0.uptime) }
        host.onDragEnded = { [unowned self] in dragEnds += 1 }
    }
}

@Suite("Live samples for the tray and shake (D-M5b-16)")
struct TriggerHostLiveSampleTests {
    @Test func onlyLiveSamplesAreHandedOut() async {
        let rig = HostRig()
        let log = HookLog(rig.host)
        rig.event(.mouseDown, at: 0, down: true, count: 5)  // pressed
        rig.event(.mouseDragged, at: 10)  // detecting
        #expect(log.samples.isEmpty)
        rig.event(.frame, at: 18, count: 6)  // live
        await rig.host.probeTask?.value
        rig.event(.frame, at: 30)
        rig.event(.frame, at: 70, mods: .shift)  // the wheel shows
        rig.event(.frame, at: 90)
        rig.scheduler.send(.escape)  // back to live
        rig.event(.frame, at: 100, mods: [])
        #expect(log.samples == [.milliseconds(18), .milliseconds(30), .milliseconds(100)])
    }

    @Test func theHandedOutSampleCarriesThePointer() async {
        let rig = HostRig()
        var seen: [Point2D] = []
        rig.host.onLiveSample = { seen.append($0.location) }
        await rig.startFileDrag()
        rig.input.location = Point2D(x: 900, y: 1150)
        rig.event(.frame, at: 30)
        #expect(seen.last == Point2D(x: 900, y: 1150))
    }

    @Test func aPassiveDragHandsOutNothing() {
        let rig = HostRig()
        rig.input.fileTypesPresent = false
        let log = HookLog(rig.host)
        rig.event(.mouseDown, at: 0, down: true, count: 5)
        rig.event(.mouseDragged, at: 10)
        rig.event(.frame, at: 18, count: 6)
        rig.event(.frame, at: 30)
        rig.event(.mouseUp, at: 40, down: false)
        #expect(log.samples.isEmpty && log.dragEnds == 0)
    }

    @Test func aLiveDragEndingIsReportedOnce() async {
        let rig = HostRig()
        let log = HookLog(rig.host)
        await rig.startFileDrag()
        rig.event(.frame, at: 30)
        rig.event(.mouseUp, at: 40, down: false)
        rig.event(.mouseDown, at: 50, down: true, count: 7)
        #expect(log.dragEnds == 1)
    }

    @Test func aWheelDragEndingIsReportedOnce() async {
        let rig = HostRig()
        let log = HookLog(rig.host)
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .control)
        rig.event(.mouseUp, at: 90, down: false, inside: false)
        #expect(log.dragEnds == 1)
    }

    @Test func aDropOnTheWheelEndsTheDragWhenItIsHandled() async {
        let rig = HostRig()
        let log = HookLog(rig.host)
        await rig.startFileDrag()
        rig.event(.frame, at: 70, mods: .shift)
        rig.event(.mouseUp, at: 90, down: false, inside: true)
        #expect(log.dragEnds == 0)
        rig.scheduler.send(.dropHandled)
        #expect(log.dragEnds == 1)
    }

    @Test func pauseStopsTheHooks() async {
        let rig = HostRig()
        let log = HookLog(rig.host)
        await rig.startFileDrag()
        rig.host.stop()
        rig.event(.frame, at: 30)
        rig.event(.mouseUp, at: 40, down: false)
        #expect(log.samples == [.milliseconds(18)] && log.dragEnds == 0)
    }
}
