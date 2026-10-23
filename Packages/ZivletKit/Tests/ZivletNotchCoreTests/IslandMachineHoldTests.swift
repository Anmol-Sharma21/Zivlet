import Testing
import ZivletNotchCore

@Suite("Island machine: holds by focus and drag (D-N13, D-M5a-4)")
struct IslandMachineHoldTests {
    let t0 = Duration.seconds(100)

    @Test func accessibilityFocusExpandsAtOnceAndHolds() {
        let (m, effects) = IslandMachine.showing(.collapsed, at: t0).handling(.accessibilityFocused(now: t0))
        #expect(m.surface == .expanded && m.isHeld)
        #expect(effects == [.show(.expanded, display: 1, contentHeight: 108), .held(true)])
    }

    @Test func losingAccessibilityFocusActsAsThePointerLeaving() {
        let focused = IslandMachine.showing(.collapsed, at: t0).after([.accessibilityFocused(now: t0)])
        let (leaving, effects) = focused.handling(.accessibilityUnfocused(now: t0 + .seconds(1)))
        #expect(effects == [.schedule(t0 + .milliseconds(1_300)), .held(false)])
        #expect(leaving.handling(.tick(now: t0 + .milliseconds(1_299))).0.surface == .expanded)
        #expect(leaving.handling(.tick(now: t0 + .milliseconds(1_300))).0.surface == .collapsed)
    }

    @Test func focusWhileTheWheelShowsHoldsWithoutExpanding() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([.wheelShown(now: t0)])
        let (next, effects) = m.handling(.accessibilityFocused(now: t0))
        #expect(next.surface == .collapsed && effects == [.held(true)])
    }

    @Test func aDragFromTheIslandHoldsItPastTheGraceAndTheLinger() {
        var m = IslandMachine.showing(.toast, at: t0).handling(.pointerEntered(now: t0)).0
        m = m.handling(.tick(now: t0 + .milliseconds(150))).0.handling(.dragBegan(now: t0 + .seconds(1))).0
        m = m.handling(.pointerExited(now: t0 + .seconds(1))).0.handling(.tick(now: t0 + .seconds(10))).0
        #expect(m.surface == .expanded && m.isHeld)
    }

    @Test func theEndOfADragOutsideStartsTheGraceAndReleasesTheHold() {
        let m = IslandMachine.showing(.toast, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)), .dragBegan(now: t0 + .seconds(1)),
            .pointerExited(now: t0 + .seconds(1)), .tick(now: t0 + .seconds(2)),
        ])
        let (ended, effects) = m.handling(.dragEnded(now: t0 + .seconds(9)))
        #expect(effects == [.schedule(t0 + .milliseconds(9_300)), .held(false)])
        #expect(ended.handling(.tick(now: t0 + .milliseconds(9_300))).0.surface == .toast)
    }

    @Test func theEndOfADragInsideKeepsTheIslandOpen() {
        let m = IslandMachine.showing(.toast, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)), .dragBegan(now: t0 + .seconds(1)),
        ])
        let (ended, effects) = m.handling(.dragEnded(now: t0 + .seconds(2)))
        #expect(effects.isEmpty && ended.surface == .expanded && ended.isHovered)
    }

    @Test func theMenuCommandHoldsTheIslandSoASavedResultWaits() {
        let (opened, effects) = IslandMachine.showing(.toast, at: t0).handling(.expandRequested(now: t0))
        #expect(
            opened.isHeld && effects == [.show(.expanded, display: 1, contentHeight: 108), .held(true), .becomeKey])
        let (away, released) = opened.handling(.resignedKey(now: t0 + .seconds(3)))
        #expect(!away.isHeld && released == [.held(false)] && away.surface == .expanded)
    }

    @Test func aClickedCardThatCollapsesAfterTheGraceGivesTheKeyboardBack() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)), .clicked(now: t0 + .seconds(1)),
            .pointerExited(now: t0 + .seconds(2)),
        ])
        #expect(m.isHeld && m.isKeyed)
        let (next, effects) = m.handling(.tick(now: t0 + .milliseconds(2_300)))
        #expect(next.surface == .collapsed && !next.isKeyed && !next.isHeld)
        #expect(effects == [.show(.collapsed, display: 1, contentHeight: 108), .held(false), .resignKey])
    }

    @Test func aKeyedCardSentBackByANewRestingSurfaceGivesTheKeyboardBack() {
        let m = IslandMachine.showing(.collapsed, at: t0).after([.clicked(now: t0)])
        let (next, effects) = m.handling(.request(.hud(.toast), now: t0 + .seconds(1)))
        #expect(next.surface == .toast && !next.isKeyed && effects.contains(.resignKey))
    }

    @Test func aWithdrawalDuringADragWaitsForTheDragToEnd() {
        let m = IslandMachine.showing(.toast, at: t0).after([
            .pointerEntered(now: t0), .tick(now: t0 + .milliseconds(150)), .dragBegan(now: t0 + .seconds(1)),
            .pointerExited(now: t0 + .seconds(1)),
        ])
        let (withdrawn, effects) = m.handling(.request(nil, now: t0 + .seconds(2)))
        #expect(effects.isEmpty && withdrawn.surface == .expanded)
        let (ended, endEffects) = withdrawn.handling(.dragEnded(now: t0 + .seconds(3)))
        #expect(ended.surface == .hidden && endEffects.contains(.hide) && endEffects.contains(.held(false)))
    }
}
