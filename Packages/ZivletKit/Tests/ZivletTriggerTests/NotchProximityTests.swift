import DragTraceSupport
import Testing
import ZivletCore

@testable import ZivletTrigger

@Suite("Notch proximity (P2-143, D-M5b-9)")
struct NotchProximityTests {
    let zone = NotchProximity.Zone(display: 1, rect: Rect2D(x: 750, y: 1131, width: 300, height: 38))
    let onHousing = Point2D(x: 900, y: 1150)

    private func events(_ samples: [InputSample], zones: [NotchProximity.Zone]? = nil) -> [NotchProximityEvent] {
        NotchProximity(zones: zones ?? [zone], config: .provisional).events(for: samples)
    }

    @Test func theProvisionalRuleIsTheDecidedOne() {
        let config = NotchProximity.Config.provisional
        #expect(config.margin == 40 && config.dwell == .milliseconds(100))
        #expect(config.maxSpeed == 800 && config.release == 24)
    }

    @Test func restingOnTheHousingEntersAfterTheDwell() {
        let samples = Samples.rest(at: onHousing, from: .zero, for: .milliseconds(100), hz: 120)
        #expect(events(samples) == [.entered(display: 1)])
    }

    @Test func itEntersOnTheSampleThatReachesTheDwell() {
        let samples = Samples.rest(at: onHousing, from: .zero, for: .milliseconds(100), hz: 120)
        var proximity = NotchProximity(zones: [zone], config: .provisional)
        var enteredAt: Int?
        for (index, sample) in samples.enumerated() {
            let (next, event) = proximity.observing(sample)
            if event != nil, enteredAt == nil { enteredAt = index }
            proximity = next
        }
        #expect(enteredAt == samples.count - 1)
        #expect(proximity.entered == 1)
    }

    @Test func ninetyNineMillisecondsIsNotEnough() {
        let samples = Samples.rest(at: onHousing, from: .zero, for: .milliseconds(99), hz: 1000)
        #expect(events(samples).isEmpty)
    }

    @Test func aPassOnTheWayToTheMenuBarOpensNothing() {
        let samples = Samples.line(
            from: Point2D(x: 600, y: 900), to: Point2D(x: 1200, y: 1168), over: .milliseconds(300))
        #expect(events(samples).isEmpty)
    }

    @Test func aSlowDriftAcrossTheZoneAt900PointsPerSecondDoesNotEnter() {
        let samples = Samples.line(
            from: Point2D(x: 700, y: 1150), to: Point2D(x: 1100, y: 1150), over: .milliseconds(444))
        #expect(events(samples).isEmpty)
    }

    @Test func aDriftAt700PointsPerSecondEnters() {
        let samples = Samples.line(
            from: Point2D(x: 700, y: 1150), to: Point2D(x: 1100, y: 1150), over: .milliseconds(571))
        #expect(events(samples) == [.entered(display: 1), .left(display: 1)])
    }

    @Test func aFastMoveInsideTheZoneRestartsTheClock() {
        let first = Samples.rest(at: onHousing, from: .seconds(1), for: .milliseconds(60))
        let jump = Samples.sample(at: Point2D(x: 1000, y: 1150), uptime: .seconds(1) + .milliseconds(68))
        let second = Samples.rest(
            at: Point2D(x: 1000, y: 1150), from: .seconds(1) + .milliseconds(76), for: .milliseconds(90))
        #expect(events(first + [jump] + second).isEmpty)
        let longer = Samples.rest(
            at: Point2D(x: 1000, y: 1150), from: .seconds(1) + .milliseconds(76), for: .milliseconds(100))
        #expect(events(first + [jump] + longer) == [.entered(display: 1)])
    }

    @Test func smallSlipsDoNotClose() {
        let rest = Samples.rest(at: onHousing, from: .seconds(1), for: .milliseconds(120))
        let slip = Samples.rest(at: Point2D(x: 900, y: 1131 - 23), from: .seconds(2), for: .milliseconds(50))
        #expect(events(rest + slip) == [.entered(display: 1)])
        let away = Samples.rest(at: Point2D(x: 900, y: 1131 - 25), from: .seconds(2), for: .milliseconds(50))
        #expect(events(rest + away) == [.entered(display: 1), .left(display: 1)])
    }

    @Test func leavingSidewaysAlsoCloses() {
        let rest = Samples.rest(at: onHousing, from: .seconds(1), for: .milliseconds(120))
        let away = Samples.sample(at: Point2D(x: 1050 + 30, y: 1150), uptime: .seconds(2))
        #expect(events(rest + [away]) == [.entered(display: 1), .left(display: 1)])
    }

    @Test func aPointerPinnedToTheTopEdgeIsInTheZone() {
        let samples = Samples.rest(at: Point2D(x: 900, y: 1169), from: .seconds(1), for: .milliseconds(120))
        #expect(events(samples) == [.entered(display: 1)])
    }

    @Test func twoZonesOnTwoDisplaysReportTheRightDisplay() {
        let pill = NotchProximity.Zone(display: 2, rect: Rect2D(x: -1100, y: 1055, width: 280, height: 25))
        let samples = Samples.rest(at: Point2D(x: -960, y: 1065), from: .seconds(1), for: .milliseconds(150))
        #expect(events(samples, zones: [zone, pill]) == [.entered(display: 2)])
    }

    @Test func samplesThatDoNotMoveTimeForwardAreIgnored() {
        let rest = Samples.rest(at: onHousing, from: .seconds(1), for: .milliseconds(50))
        let stale = Samples.sample(at: Point2D(x: 100, y: 100), uptime: .seconds(1))
        let more = Samples.rest(at: onHousing, from: .seconds(1) + .milliseconds(58), for: .milliseconds(50))
        #expect(events(rest + [stale] + more) == [.entered(display: 1)])
    }

    @Test func resetForgetsTheDwellAndTheEntry() {
        let half = Samples.rest(at: onHousing, from: .seconds(1), for: .milliseconds(60))
        let rest = Samples.rest(at: onHousing, from: .seconds(2), for: .milliseconds(60))
        let started = NotchProximity(zones: [zone], config: .provisional).feeding(half)
        #expect(started.reset().events(for: rest).isEmpty)
        let entered = NotchProximity(zones: [zone], config: .provisional).feeding(half + rest)
        #expect(entered.entered == 1)
        #expect(entered.reset().entered == nil)
    }

    @Test func newZonesForgetTheOldOnes() {
        let moved = NotchProximity.Zone(display: 1, rect: Rect2D(x: 0, y: 0, width: 100, height: 38))
        let proximity = NotchProximity(zones: [zone], config: .provisional).replacingZones([moved])
        #expect(proximity.zones == [moved])
        let samples = Samples.rest(at: onHousing, from: .seconds(1), for: .milliseconds(150))
        #expect(proximity.events(for: samples).isEmpty)
    }

    @Test func noSpeedLimitAcceptsAnySpeed() {
        let config = NotchProximity.Config(margin: 40, dwell: .milliseconds(100), maxSpeed: nil, release: 24)
        let samples = Samples.line(
            from: Point2D(x: 750, y: 1150), to: Point2D(x: 1049, y: 1150), over: .milliseconds(120))
        #expect(NotchProximity(zones: [zone], config: config).events(for: samples) == [.entered(display: 1)])
    }
}
