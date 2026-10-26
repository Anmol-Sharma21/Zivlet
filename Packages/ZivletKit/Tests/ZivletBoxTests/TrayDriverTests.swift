import Foundation
import Testing
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletTrigger

@testable import ZivletBox

@Suite("Tray driver: live samples to the tray and the shake (D-M5b-16)")
@MainActor
struct TrayDriverTests {
    /// The off-screen notch display's housing centre (x −4100, top y −3831).
    static let housing = Point2D(x: -4_100, y: -3_845)

    final class Recorder {
        var shakes: [Point2D] = []
        var countReads: [Int] = []
        var shakeToOpen = false
    }

    private func driver(_ rig: TrayRig, _ recorder: Recorder) -> TrayDriver {
        TrayDriver(
            tray: rig.tray, zones: TrayDriver.zones(for: rig.hosts.displayIDs.compactMap(rig.hosts.display)),
            shakeToOpen: { recorder.shakeToOpen }, openForShake: { recorder.shakes.append($0) },
            itemCount: { changeCount in
                recorder.countReads.append(changeCount)
                return 3
            })
    }

    private func sample(_ point: Point2D, ms: Int, change: Int = 1) -> InputSample {
        InputSample(
            uptime: .seconds(10) + .milliseconds(ms), source: .frame, primaryButtonDown: true, dragChangeCount: change,
            dragHasFileTypes: true, location: point)
    }

    private func rest(at point: Point2D, from start: Int, for ms: Int, change: Int = 1) -> [InputSample] {
        stride(from: start, through: start + ms, by: 8).map { sample(point, ms: $0, change: change) }
    }

    /// Four ±60 pt swings at 6 Hz around x −4100, y −4400 (well under the notch).
    private func shake(from start: Int) -> [InputSample] {
        (0..<48).map { frame in
            let t = Double(frame) / 120
            let x = -4_100 + 60 * sin(2 * .pi * 6 * min(t, 4.0 / 12))
            return sample(Point2D(x: x, y: -4_400), ms: start + frame * 8)
        }
    }

    @Test func zonesComeFromTheIslandLayoutWithTheProvisionalMargin() throws {
        let rig = try TrayRig(boxItems: 0)
        let displays = rig.hosts.displayIDs.compactMap(rig.hosts.display)
        let zones = TrayDriver.zones(for: displays)
        #expect(zones.map(\.display) == [1, 2])
        #expect(
            zones.first?.rect
                == IslandLayout.trayZone(on: displays[0], margin: NotchProximity.Config.provisional.margin))
    }

    @Test func samplesRestingOnTheHousingOpenTheDropTarget() throws {
        let rig = try TrayRig(boxItems: 5)
        let recorder = Recorder()
        let driver = driver(rig, recorder)
        for sample in rest(at: Self.housing, from: 0, for: 300) { driver.observe(sample) }
        #expect(rig.hosts.surface(on: 1) == .dropTarget)
        #expect(recorder.countReads == [1])
        #expect(rig.tray.accessibilityValue(display: 1) == "Add 3 items to the Drop Box")
    }

    @Test func aShakeOpensThePanelOnlyWithTheSettingOn() throws {
        let rig = try TrayRig(boxItems: 0)
        let recorder = Recorder()
        let driver = driver(rig, recorder)
        for sample in shake(from: 0) { driver.observe(sample) }
        #expect(recorder.shakes.isEmpty)
        driver.dragEnded()
        recorder.shakeToOpen = true
        for sample in shake(from: 2_000) { driver.observe(sample) }
        #expect(recorder.shakes.count == 1)
    }

    @Test func whileTheWheelShowsNeitherFires() throws {
        let rig = try TrayRig(boxItems: 5)
        let recorder = Recorder()
        recorder.shakeToOpen = true
        let driver = driver(rig, recorder)
        driver.wheelShown()
        for sample in rest(at: Self.housing, from: 0, for: 300) + shake(from: 400) { driver.observe(sample) }
        #expect(rig.hosts.surface(on: 1) == .sensor && recorder.shakes.isEmpty)
    }

    @Test func afterTheWheelOnlyANewApproachOpensTheTray() throws {
        let rig = try TrayRig(boxItems: 5)
        let driver = driver(rig, Recorder())
        for sample in rest(at: Self.housing, from: 0, for: 300) { driver.observe(sample) }
        driver.wheelShown()
        #expect(rig.hosts.surface(on: 1) == .sensor)
        driver.wheelHidden(at: .seconds(10) + .milliseconds(400))
        for sample in rest(at: Self.housing, from: 500, for: 300) { driver.observe(sample) }
        #expect(rig.hosts.surface(on: 1) == .sensor)
        for sample in rest(at: Point2D(x: -4_100, y: -4_400), from: 900, for: 50) { driver.observe(sample) }
        for sample in rest(at: Self.housing, from: 1_000, for: 300) { driver.observe(sample) }
        #expect(rig.hosts.surface(on: 1) == .dropTarget)
    }

    @Test func aDragEndResetsBothDetectorsAndTheTray() throws {
        let rig = try TrayRig(boxItems: 5)
        let recorder = Recorder()
        recorder.shakeToOpen = true
        let driver = driver(rig, recorder)
        for sample in rest(at: Self.housing, from: 0, for: 300) { driver.observe(sample) }
        #expect(rig.hosts.surface(on: 1) == .dropTarget)
        for sample in shake(from: 400) { driver.observe(sample) }
        #expect(recorder.shakes.count == 1)
        driver.dragEnded()
        #expect(rig.hosts.surface(on: 1) == .sensor)
        for sample in rest(at: Self.housing, from: 2_000, for: 120, change: 2) { driver.observe(sample) }
        #expect(rig.hosts.surface(on: 1) == .sensor)
        for sample in shake(from: 3_000) { driver.observe(sample) }
        #expect(recorder.shakes.count == 2)
    }

    @Test func theItemCountIsReadOncePerDrag() throws {
        let rig = try TrayRig(boxItems: 5)
        let recorder = Recorder()
        let driver = driver(rig, recorder)
        for sample in rest(at: Self.housing, from: 0, for: 300) { driver.observe(sample) }
        driver.dragEnded()
        for sample in rest(at: Self.housing, from: 1_000, for: 300, change: 7) { driver.observe(sample) }
        #expect(recorder.countReads == [1, 7])
    }

    @Test func zonesFollowADisplayChange() throws {
        let rig = try TrayRig(boxItems: 5)
        let driver = driver(rig, Recorder())
        driver.zonesChanged([])
        for sample in rest(at: Self.housing, from: 0, for: 300) { driver.observe(sample) }
        #expect(rig.hosts.surface(on: 1) == .sensor)
        driver.zonesChanged(TrayDriver.zones(for: rig.hosts.displayIDs.compactMap(rig.hosts.display)))
        for sample in rest(at: Self.housing, from: 400, for: 300) { driver.observe(sample) }
        #expect(rig.hosts.surface(on: 1) == .dropTarget)
    }
}
