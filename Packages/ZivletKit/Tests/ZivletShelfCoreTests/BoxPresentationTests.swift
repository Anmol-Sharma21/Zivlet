import Testing

@testable import ZivletShelfCore

@Suite("Box presentation (P2-55 states)")
struct BoxPresentationTests {
    @Test func escapeStepsDownOneState() {
        let open = BoxPresentation(base: .expanded)
        #expect(open.handling(.escape).0.base == .collapsed)
        #expect(BoxPresentation(base: .expanded, dock: .right).handling(.escape).0.base == .docked(.right))
        #expect(BoxPresentation(base: .collapsed).handling(.escape).0.base == .hidden)
    }

    @Test func aDropTargetReturnsToWhatItInterrupted() {
        let docked = BoxPresentation(base: .docked(.left), dock: .left)
        let hovering = docked.handling(.dragEntered(count: 3)).0
        #expect(hovering.overlay == .dropTarget(count: 3))
        #expect(hovering.handling(.dragExited).0 == docked)
        #expect(hovering.handling(.dropped).0.base == .expanded)
    }

    @Test func showingAHiddenBoxGoesBackToItsDock() {
        #expect(BoxPresentation(base: .hidden, dock: .right).handling(.show).0.base == .docked(.right))
        #expect(BoxPresentation(base: .hidden).handling(.show).0.base == .expanded)
    }

    @Test func missingItemsRaiseAttentionWithoutChangingTheBase() {
        let next = BoxPresentation(base: .expanded).handling(.itemsChanged(count: 12, missing: 2)).0
        #expect(next.base == .expanded && next.missing == 2 && !next.isEmpty && next.needsAttention)
        #expect(BoxPresentation(base: .expanded).handling(.itemsChanged(count: 0, missing: 0)).0.isEmpty)
    }

    @Test func progressStaysBetweenZeroAndOne() {
        let busy = BoxPresentation(base: .expanded).handling(.busyStarted(verb: "Moving")).0
        #expect(busy.handling(.progress(1.7)).0.overlay == .busy(verb: "Moving", fraction: 1))
        #expect(busy.handling(.progress(-1)).0.overlay == .busy(verb: "Moving", fraction: 0))
        #expect(busy.handling(.progress(.nan)).0.overlay == .busy(verb: "Moving", fraction: 0))
    }

    @Test func aDropIsAcceptedOnlyWhileTheTargetShows() {
        #expect(BoxPresentation(base: .expanded, overlay: .dropTarget(count: 1)).acceptsDrop)
        #expect(!BoxPresentation(base: .expanded).acceptsDrop)
    }

    @Test func everyEventHasARowForEveryState() { BoxPresentationTable.assertComplete() }
}
