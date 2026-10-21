import Testing
import ZivletNotchCore

@Suite("Island machine: hover intent and grace (design/19 §4.4)")
struct IslandMachineHoverTests {
    let t0 = Duration.seconds(100)

    @Test func hoverExpandsOnlyAfterTheIntentDelay() {
        var m = IslandMachine().handling(.request(.hud(.collapsed), now: t0)).0
        m = m.handling(.pointerEntered(now: t0)).0
        #expect(m.handling(.tick(now: t0 + .milliseconds(149))).0.surface == .collapsed)
        #expect(m.handling(.tick(now: t0 + .milliseconds(150))).0.surface == .expanded)
    }

    @Test func enteringSchedulesTheIntentAndHolds() {
        let (_, effects) = IslandMachine.showing(.collapsed, at: t0).handling(.pointerEntered(now: t0))
        #expect(effects == [.schedule(t0 + IslandMachine.Timing.intent), .held(true)])
        #expect(IslandMachine.Timing.intent == .milliseconds(150) && IslandMachine.Timing.grace == .milliseconds(300))
    }

    @Test func passingThroughOpensNothing() {
        var m = IslandMachine().handling(.request(.hud(.collapsed), now: t0)).0
        m = m.handling(.pointerEntered(now: t0)).0
        let (left, effects) = m.handling(.pointerExited(now: t0 + .milliseconds(80)))
        #expect(effects.contains(.cancelDeadline))
        #expect(left.handling(.tick(now: t0 + .seconds(1))).0.surface == .collapsed)
    }

    @Test func leavingCollapsesAfterTheGrace() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)), .pointerExited(now: t0 + .seconds(1)),
        ])
        #expect(m.handling(.tick(now: t0 + .milliseconds(1_299))).0.surface == .expanded)
        let (collapsed, effects) = m.handling(.tick(now: t0 + .milliseconds(1_300)))
        #expect(collapsed.surface == .collapsed && effects == [.show(.collapsed, display: 1, contentHeight: 108)])
    }

    @Test func reenteringDuringTheGraceKeepsItOpen() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)), .pointerExited(now: t0 + .seconds(1)),
        ])
        let (back, effects) = m.handling(.pointerEntered(now: t0 + .milliseconds(1_100)))
        #expect(effects == [.cancelDeadline, .held(true)])
        #expect(back.handling(.tick(now: t0 + .seconds(2))).0.surface == .expanded)
    }

    @Test func aNewRequestWhileHoveredKeepsTheIslandExpanded() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)),
        ])
        let (next, effects) = m.handling(.request(.hud(.toast), now: t0 + .seconds(1)))
        #expect(next.surface == .expanded && effects.isEmpty && next.request == .hud(.toast))
        let left = next.after([.pointerExited(now: t0 + .seconds(2)), .tick(now: t0 + .seconds(3))])
        #expect(left.surface == .toast)
    }

    @Test func aToastExpandsOnHoverAndReturnsToTheToast() {
        let m = IslandMachine.showing(.toast, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)),
        ])
        #expect(m.surface == .expanded)
        let back = m.after([.pointerExited(now: t0 + .seconds(1)), .tick(now: t0 + .seconds(2))])
        #expect(back.surface == .toast && !back.isHovered)
    }
}
