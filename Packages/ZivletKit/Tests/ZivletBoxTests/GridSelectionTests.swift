import Foundation
import Testing
import ZivletCore

@testable import ZivletBox

@Suite("Grid selection: click, ⇧, ⌘, arrows, marquee (17e §2.3)")
struct GridSelectionTests {
    private let ids = (0..<12).map { _ in UUID() }

    @Test func aPlainClickSelectsOne() {
        let next = GridSelection().clicking(ids[3], extend: false, toggle: false, in: ids)
        #expect(next.selected == [ids[3]] && next.anchor == ids[3])
    }

    @Test func shiftClickSelectsTheRangeFromTheAnchor() {
        let next = GridSelection().clicking(ids[2], extend: false, toggle: false, in: ids)
            .clicking(ids[5], extend: true, toggle: false, in: ids)
        #expect(next.selected == Set(ids[2...5]) && next.anchor == ids[2])
        let back = next.clicking(ids[0], extend: true, toggle: false, in: ids)
        #expect(back.selected == Set(ids[0...2]))
    }

    @Test func commandClickTogglesOne() {
        let one = GridSelection().clicking(ids[1], extend: false, toggle: false, in: ids)
        let two = one.clicking(ids[4], extend: false, toggle: true, in: ids)
        #expect(two.selected == [ids[1], ids[4]])
        #expect(two.clicking(ids[1], extend: false, toggle: true, in: ids).selected == [ids[4]])
    }

    @Test func selectAllAndClear() {
        #expect(GridSelection().all(ids).selected == Set(ids))
        #expect(GridSelection().all(ids).cleared() == GridSelection())
    }

    @Test func arrowsMoveByOneOrByARow() {
        let start = GridSelection().clicking(ids[6], extend: false, toggle: false, in: ids)
        #expect(start.moving(.right, extend: false, in: ids, columns: 5).selected == [ids[7]])
        #expect(start.moving(.left, extend: false, in: ids, columns: 5).selected == [ids[5]])
        #expect(start.moving(.up, extend: false, in: ids, columns: 5).selected == [ids[1]])
        #expect(start.moving(.down, extend: false, in: ids, columns: 5).selected == [ids[11]])
        #expect(start.moving(.down, extend: false, in: ids, columns: 1).selected == [ids[7]])
    }

    @Test func arrowsStopAtTheEnds() {
        let first = GridSelection().clicking(ids[0], extend: false, toggle: false, in: ids)
        #expect(first.moving(.up, extend: false, in: ids, columns: 5).selected == [ids[0]])
        #expect(first.moving(.left, extend: false, in: ids, columns: 5).selected == [ids[0]])
        let last = GridSelection().clicking(ids[11], extend: false, toggle: false, in: ids)
        #expect(last.moving(.down, extend: false, in: ids, columns: 5).selected == [ids[11]])
    }

    @Test func shiftArrowsExtendFromTheAnchor() {
        let start = GridSelection().clicking(ids[2], extend: false, toggle: false, in: ids)
        let next = start.moving(.right, extend: true, in: ids, columns: 5).moving(
            .right, extend: true, in: ids, columns: 5)
        #expect(next.selected == Set(ids[2...4]) && next.anchor == ids[2])
    }

    @Test func anArrowWithoutASelectionPicksTheFirstItem() {
        #expect(GridSelection().moving(.down, extend: false, in: ids, columns: 5).selected == [ids[0]])
        #expect(GridSelection().moving(.down, extend: false, in: [], columns: 5) == GridSelection())
    }

    @Test func theMarqueeSelectsTheCellsItTouches() {
        let cells = GridSelection.cellFrames(count: 7, columns: 5, cell: 64, rowHeight: 66, gap: 8)
        #expect(cells.count == 7 && cells[5] == Rect2D(x: 0, y: 74, width: 64, height: 66))
        let hit = GridSelection.marquee(Rect2D(x: 60, y: 60, width: 20, height: 20), cells: cells)
        #expect(hit == [0, 1, 5, 6])
        #expect(GridSelection.marquee(Rect2D(x: 400, y: 400, width: 5, height: 5), cells: cells).isEmpty)
    }

    @Test func anItemThatLeftTheBoxLeavesTheSelection() {
        let all = GridSelection().all(ids)
        #expect(all.keeping(Array(ids.prefix(3))).selected == Set(ids.prefix(3)))
    }
}

@Suite("Type to select (0.8 s reset)")
struct TypeSelectTests {
    private let names: [(UUID, String)] = [
        (UUID(), "alpha.png"), (UUID(), "Beta.pdf"), (UUID(), "beach.mov"), (UUID(), "gamma.txt"),
    ]

    @Test func lettersTypedTogetherBuildOnePrefix() {
        let typed = TypeSelect().typing("b", at: 0).typing("e", at: 0.3).typing("a", at: 0.6)
        #expect(typed.prefix == "bea" && typed.match(in: names) == names[2].0)
    }

    @Test func aPauseOfPoint8SecondsStartsOver() {
        let typed = TypeSelect().typing("b", at: 0).typing("g", at: 0.81)
        #expect(typed.prefix == "g" && typed.match(in: names) == names[3].0)
        #expect(TypeSelect().typing("b", at: 0).typing("e", at: 0.8).prefix == "be")
    }

    @Test func matchingIgnoresCase() {
        #expect(TypeSelect().typing("B", at: 0).match(in: names) == names[1].0)
        #expect(TypeSelect().typing("z", at: 0).match(in: names) == nil)
    }
}
