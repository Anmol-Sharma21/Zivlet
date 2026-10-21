import Foundation
import Testing
import ZivletCore
import ZivletNotchCore

@Suite("Notch geometry (P2-115, design/19 §3.2)")
struct NotchGeometryTests {
    @Test func housingIsTheGapBetweenTheAuxiliaryAreas() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        #expect(NotchGeometry.housing(of: display) == Rect2D(x: 790, y: 1131, width: 220, height: 38))
        #expect(NotchGeometry.hasNotch(display))
    }

    @Test func noSafeAreaMeansNoHousing() throws {
        #expect(NotchGeometry.housing(of: try DisplayFixtures.noNotch1080()) == nil)
    }

    @Test func aSafeAreaWithoutAuxiliaryAreasGetsThePill() throws {
        #expect(!NotchGeometry.hasNotch(try DisplayFixtures.safeAreaWithoutAux()))
    }

    @Test func overlappingAuxiliaryAreasMeanNoHousing() throws {
        let display = try DisplayFixtures.make(leftWidth: 900, rightX: 800)
        #expect(NotchGeometry.housing(of: display) == nil)
    }

    @Test func nonFiniteValuesAreRefused() {
        #expect(throws: DisplayGeometry.Invalid.self) {
            try DisplayGeometry(
                id: 9, frame: Rect2D(x: 0, y: 0, width: .nan, height: 10),
                visibleFrame: Rect2D(x: 0, y: 0, width: 10, height: 10), safeAreaTop: 0,
                auxiliaryTopLeft: nil, auxiliaryTopRight: nil, isBuiltIn: false)
        }
    }

    @Test func negativeSizesAndSafeAreasAreRefused() {
        #expect(throws: DisplayGeometry.Invalid.self) {
            try DisplayGeometry(
                id: 9, frame: Rect2D(x: 0, y: 0, width: 10, height: 10),
                visibleFrame: Rect2D(x: 0, y: 0, width: 10, height: 10), safeAreaTop: -1,
                auxiliaryTopLeft: nil, auxiliaryTopRight: nil, isBuiltIn: false)
        }
        #expect(throws: DisplayGeometry.Invalid.self) {
            try DisplayGeometry(
                id: 9, frame: Rect2D(x: 0, y: 0, width: 10, height: 10),
                visibleFrame: Rect2D(x: 0, y: 0, width: 10, height: 10), safeAreaTop: 0,
                auxiliaryTopLeft: Rect2D(x: 0, y: 0, width: -3, height: 1), auxiliaryTopRight: nil, isBuiltIn: false)
        }
    }

    @Test func theBuiltInNotchLatchSurvivesTheLidClosing() throws {
        let external = try DisplayFixtures.noNotch1080()
        #expect(NotchGeometry.builtInNotchSeen(before: false, displays: [try DisplayFixtures.mbp14MoreSpace()]))
        #expect(NotchGeometry.builtInNotchSeen(before: true, displays: [external]))  // lid closed
        #expect(!NotchGeometry.builtInNotchSeen(before: false, displays: [external]))
        #expect(!NotchGeometry.builtInNotchSeen(before: false, displays: [try DisplayFixtures.safeAreaWithoutAux()]))
    }

    @Test func geometryRoundTripsThroughJSON() throws {
        let display = try DisplayFixtures.mbp14MoreSpace()
        let data = try JSONEncoder().encode(display)
        #expect(try JSONDecoder().decode(DisplayGeometry.self, from: data) == display)
    }

    @Test func decodingValidatesLikeTheInitializer() throws {
        let json =
            #"{"id":1,"frame":{"x":0,"y":0,"width":-5,"height":10},"#
            + #""visibleFrame":{"x":0,"y":0,"width":10,"height":10},"safeAreaTop":0,"isBuiltIn":false}"#
        #expect(throws: DisplayGeometry.Invalid.self) {
            try JSONDecoder().decode(DisplayGeometry.self, from: Data(json.utf8))
        }
    }
}
