import Testing
import ZivletNotchCore

@Suite("Island machine: requests and surfaces (P2-115, design/19 §4.2)")
struct IslandMachineTests {
    let t0 = Duration.seconds(100)

    @Test func aRequestShowsItsRestingSurface() {
        let (m, effects) = IslandMachine().handling(.request(.hud(.collapsed), now: t0))
        #expect(m.surface == .collapsed)
        #expect(effects.contains(.show(.collapsed, display: 1, contentHeight: 0)))
    }

    @Test func aNewHeightWhileExpandedAndHoveredReLaysOutAndKeepsTheHover() {
        var m = IslandMachine.showing(.toast, at: t0).handling(.pointerEntered(now: t0)).0
        m = m.handling(.tick(now: t0 + .milliseconds(150))).0
        let (next, effects) = m.handling(.contentHeightChanged(200, now: t0 + .seconds(1)))
        #expect(next.surface == .expanded && next.isHovered)
        #expect(effects == [.show(.expanded, display: 1, contentHeight: 200)])
    }

    @Test func withdrawingTheRequestHidesAndClearsTimers() {
        let shown = IslandMachine().handling(.request(.hud(.collapsed), now: t0)).0
        let (m, effects) = shown.handling(.request(nil, now: t0))
        #expect(m.surface == .hidden && effects.contains(.hide) && effects.contains(.cancelDeadline))
    }

    @Test func theMenuCommandExpandsMakesKeyAndStaysAfterThePointerPasses() {
        var m = IslandMachine.showing(.collapsed, at: t0)
        let (opened, effects) = m.handling(.expandRequested(now: t0))
        #expect(opened.surface == .expanded && effects.contains(.becomeKey))
        m = opened.handling(.pointerEntered(now: t0)).0.handling(.pointerExited(now: t0 + .milliseconds(10))).0
        #expect(m.handling(.tick(now: t0 + .seconds(5))).0.surface == .expanded)
    }

    @Test func thePointerLeavingAfterItEnteredCollapsesAPinnedIsland() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([
            .expandRequested(now: t0), .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)),
            .pointerExited(now: t0 + .seconds(1)),
        ])
        #expect(m.handling(.tick(now: t0 + .milliseconds(1_300))).0.surface == .collapsed)
    }

    @Test func theWheelSendsAHoverExpansionBackToItsRestingSurface() {
        let m = IslandMachine.showing(.toast, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)),
        ])
        #expect(m.surface == .expanded)
        let (next, effects) = m.handling(.wheelShown(now: t0 + .seconds(1)))
        #expect(next.surface == .toast && effects.contains(.show(.toast, display: 1, contentHeight: 108)))
    }

    @Test func theWheelLeavesAPinnedIslandOpen() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([.expandRequested(now: t0)])
        let (next, effects) = m.handling(.wheelShown(now: t0 + .seconds(1)))
        #expect(next.surface == .expanded && effects.isEmpty)
    }

    @Test func hoverIsIgnoredWhileTheWheelIsShown() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([
            .wheelShown(now: t0), .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(200)),
        ])
        #expect(m.surface == .collapsed && !m.isHovered)
        let after = m.after([
            .wheelHidden(now: t0 + .seconds(1)), .pointerEntered(now: t0 + .seconds(1)),
            .tick(now: t0 + .milliseconds(1_150)),
        ])
        #expect(after.surface == .expanded)
    }

    @Test func escapeDoesNothingBeforeAClick() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)),
        ])
        let (next, effects) = m.handling(.escape(now: t0 + .seconds(1)))
        #expect(next.surface == .expanded && effects.isEmpty)
    }

    @Test func escapeAfterAClickCollapsesAndResignsKey() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)), .clicked(now: t0 + .seconds(1)),
        ])
        let (next, effects) = m.handling(.escape(now: t0 + .seconds(2)))
        #expect(next.surface == .collapsed && effects.contains(.resignKey) && !next.isKeyed)
        #expect(!effects.contains(.closeRequested(.hud)))
    }

    @Test func escapeOnAClosableCardAsksTheClientToClose() {
        let m = IslandMachine.showing(.collapsed, at: t0, closable: true).after([.expandRequested(now: t0)])
        let (next, effects) = m.handling(.escape(now: t0 + .seconds(1)))
        #expect(effects.contains(.closeRequested(.hud)) && effects.contains(.resignKey))
        #expect(next.surface == .collapsed)
    }

    @Test func resigningKeyClearsKeyedSoEscapeIsIgnoredAgain() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)), .clicked(now: t0 + .seconds(1)),
            .resignedKey(now: t0 + .seconds(2)),
        ])
        let (next, effects) = m.handling(.escape(now: t0 + .seconds(3)))
        #expect(effects.isEmpty && next.surface == .expanded)
    }

    @Test func aClickAllowsTheKeyWindowOnce() {
        let (m, effects) = IslandMachine.showing(.collapsed, at: t0).handling(.clicked(now: t0))
        #expect(m.isKeyed && effects == [.held(true), .becomeKeyAllowed])
        #expect(m.handling(.clicked(now: t0 + .seconds(1))).1.isEmpty)
    }

    @Test func reduceMotionChangesOnlyTheNextTransition() {
        let (m, effects) = IslandMachine.showing(.collapsed, at: t0).handling(.reduceMotionChanged(true, now: t0))
        #expect(effects.isEmpty)
        #expect(m.motion == IslandMotion(reduceMotion: true))
        #expect(m.handling(.reduceMotionChanged(false, now: t0)).0.motion == IslandMotion(reduceMotion: false))
    }

    @Test func aNewRestingSurfaceReLaysOutAndTheSameOneDoesNot() {
        let m = IslandMachine.showing(.collapsed, at: t0)
        let (toast, effects) = m.handling(.request(.hud(.toast), now: t0))
        #expect(toast.surface == .toast && effects == [.show(.toast, display: 1, contentHeight: 108)])
        #expect(toast.handling(.request(.hud(.toast), now: t0)).1.isEmpty)
    }

    @Test func aHiddenRestingSurfaceIsAWithdrawal() {
        let (m, effects) = IslandMachine.showing(.collapsed, at: t0).handling(.request(.hud(.hidden), now: t0))
        #expect(m.surface == .hidden && m.request == nil && effects.contains(.hide))
    }

    @Test func everyStepSchedulesAtMostOneDeadline() {
        let script: [IslandEvent] = [
            .request(.hud(.collapsed), now: t0), .pointerEntered(now: t0), .accessibilityFocused(now: t0),
            .pointerExited(now: t0 + .milliseconds(50)), .accessibilityUnfocused(now: t0 + .milliseconds(60)),
            .pointerEntered(now: t0 + .milliseconds(100)), .tick(now: t0 + .milliseconds(400)),
            .dragBegan(now: t0 + .seconds(1)), .pointerExited(now: t0 + .seconds(1)), .dragEnded(now: t0 + .seconds(2)),
            .request(.hud(.toast), now: t0 + .seconds(2)), .tick(now: t0 + .seconds(3)),
            .request(nil, now: t0 + .seconds(4)),
        ]
        var machine = IslandMachine()
        for event in script {
            let (next, effects) = machine.handling(event)
            let deadlines = effects.filter {
                if case .schedule = $0 { return true }
                return $0 == .cancelDeadline
            }
            #expect(deadlines.count <= 1)
            machine = next
        }
    }
}
