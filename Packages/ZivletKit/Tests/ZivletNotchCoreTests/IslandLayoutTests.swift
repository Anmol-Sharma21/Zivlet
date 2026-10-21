import Testing
import ZivletCore
import ZivletNotchCore

@Suite("Island layout (P2-115, design/19 §3.4)")
struct IslandLayoutTests {
    @Test func collapsedIsTheHousingWithShouldersAndATabBelow() throws {
        let frame = IslandLayout.frame(.collapsed, on: try DisplayFixtures.mbp14MoreSpace())
        #expect(frame == Rect2D(x: 784, y: 1107, width: 232, height: 62))
    }

    @Test func collapsedContentSitsInTheTabNeverInsideTheHousing() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        #expect(IslandLayout.tab(on: display) == Rect2D(x: 790, y: 1107, width: 220, height: 24))
    }

    @Test func collapsedCoversAtMostSixPointsOfMenuBarEachSide() throws {  // design/19 §5.3 acceptance rule
        let display = try DisplayFixtures.mbp14MoreSpace()
        let housing = try #require(NotchGeometry.housing(of: display))
        let frame = IslandLayout.frame(.collapsed, on: display)
        #expect(frame.minX >= housing.minX - 6 && frame.maxX <= housing.maxX + 6)
    }

    @Test func toastHangsBelowTheHousing() throws {
        let frame = IslandLayout.frame(.toast, on: try DisplayFixtures.mbp14MoreSpace())
        #expect(frame == Rect2D(x: 720, y: 1095, width: 360, height: 74))
    }

    @Test func expandedHeightFollowsTheContentUpTo320() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        #expect(IslandLayout.frame(.expanded, on: display, contentHeight: 108).height == 146)
        #expect(IslandLayout.frame(.expanded, on: display, contentHeight: 108).width == 380)
        #expect(IslandLayout.frame(.expanded, on: display, contentHeight: 900).height == 320)
        #expect(IslandLayout.contentScrolls(contentHeight: 900, on: display))
        #expect(!IslandLayout.contentScrolls(contentHeight: 108, on: display))
    }

    @Test func thePillSitsSixPointsUnderTheMenuBar() throws {
        let frame = IslandLayout.frame(.collapsed, on: try DisplayFixtures.noNotch1080())
        #expect(frame == Rect2D(x: -1060, y: 1021, width: 200, height: 28))
    }

    @Test func thePillToastAndCardShareItsTop() throws {
        let display = try DisplayFixtures.noNotch1080()
        #expect(IslandLayout.frame(.toast, on: display) == Rect2D(x: -1140, y: 1009, width: 360, height: 40))
        #expect(
            IslandLayout.frame(.expanded, on: display, contentHeight: 100)
                == Rect2D(
                    x: -1150, y: 949, width: 380, height: 100))
        #expect(IslandLayout.frame(.expanded, on: display, contentHeight: 400).height == 320)
        #expect(IslandLayout.contentScrolls(contentHeight: 330, on: display))
        #expect(IslandLayout.tab(on: display) == IslandLayout.frame(.collapsed, on: display))
    }

    @Test func theContentStartsBelowTheHousingOnlyOnANotchDisplay() throws {
        #expect(IslandLayout.contentTopInset(on: try DisplayFixtures.mbp14MoreSpace()) == 38)
        #expect(IslandLayout.contentTopInset(on: try DisplayFixtures.noNotch1080()) == 0)
    }

    @Test func aHiddenIslandKeepsTheCollapsedFrame() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        #expect(IslandLayout.frame(.hidden, on: display) == IslandLayout.frame(.collapsed, on: display))
    }

    @Test func everyFrameStaysInsideItsDisplay() throws {
        for display in try DisplayFixtures.all() {
            for surface in [IslandSurface.collapsed, .toast, .expanded] {
                let f = IslandLayout.frame(surface, on: display, contentHeight: 400)
                #expect(f.minX >= display.frame.minX && f.maxX <= display.frame.maxX)
                #expect(f.minY >= display.frame.minY && f.maxY <= display.frame.maxY)
            }
        }
    }

    @Test func theDropPointPicksItsDisplayElseTheFirst() throws {
        let displays = try DisplayFixtures.sideBySide()
        #expect(IslandLayout.display(for: Point2D(x: -100, y: 500), in: displays)?.id == 2)
        #expect(IslandLayout.display(for: Point2D(x: 9_000, y: 500), in: displays)?.id == 1)
        #expect(IslandLayout.display(for: nil, in: displays)?.id == 1)
        #expect(IslandLayout.display(for: nil, in: []) == nil)
    }
}
