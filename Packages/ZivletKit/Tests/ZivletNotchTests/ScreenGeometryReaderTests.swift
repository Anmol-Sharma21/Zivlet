import AppKit
import Foundation
import NotchTestSupport
import Testing
import ZivletCore
import ZivletNotchCore

@testable import ZivletNotch

@Suite("Screen geometry reader")
@MainActor
struct ScreenGeometryReaderTests {
    static let recorded = ScreenGeometryReader.Raw(
        number: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169),
        visible: CGRect(x: 0, y: 94, width: 1800, height: 1036), safeTop: 38,
        left: CGRect(x: 0, y: 1131, width: 790, height: 38), right: CGRect(x: 1010, y: 1131, width: 790, height: 38),
        builtIn: true)

    static let external = ScreenGeometryReader.Raw(
        number: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        visible: CGRect(x: -1920, y: 0, width: 1920, height: 1055), safeTop: 0, left: nil, right: nil,
        builtIn: false)

    @Test func mapsRawScreenValuesToDisplayGeometry() throws {
        #expect(try ScreenGeometryReader.geometry(Self.recorded, log: { _ in }) == DisplayFixtures.mbp14MoreSpace())
        #expect(try ScreenGeometryReader.geometry(Self.external, log: { _ in }) == DisplayFixtures.noNotch1080())
    }

    @Test func auxiliaryAreasRelativeToTheScreenAreMadeGlobal() throws {
        let local = ScreenGeometryReader.Raw(
            number: 7, frame: CGRect(x: 1920, y: 0, width: 1800, height: 1169),
            visible: CGRect(x: 1920, y: 94, width: 1800, height: 1036), safeTop: 38,
            left: CGRect(x: 0, y: 1131, width: 790, height: 38),
            right: CGRect(x: 1010, y: 1131, width: 790, height: 38),
            builtIn: true)
        let geometry = try #require(ScreenGeometryReader.geometry(local, log: { _ in }))
        #expect(geometry.auxiliaryTopLeft == Rect2D(x: 1920, y: 1131, width: 790, height: 38))
        #expect(NotchGeometry.housing(of: geometry) == Rect2D(x: 2710, y: 1131, width: 220, height: 38))
    }

    @Test func aScreenWithInvalidValuesIsSkippedWithOneErrorLine() {
        let broken = ScreenGeometryReader.Raw(
            number: 3, frame: CGRect(x: 0, y: 0, width: Double.nan, height: 900),
            visible: CGRect(x: 0, y: 0, width: 100, height: 900), safeTop: 0, left: nil, right: nil, builtIn: false)
        var lines: [String] = []
        let displays = ScreenGeometryReader.geometries([broken, Self.external], log: { lines.append($0) })
        #expect(displays.map(\.id) == [2])
        #expect(lines.count == 1 && lines[0].contains("frame.width"))
    }

    @Test func aSecondScreenWithTheSameNumberIsSkippedWithOneErrorLine() {
        var lines: [String] = []
        let displays = ScreenGeometryReader.geometries([Self.external, Self.external], log: { lines.append($0) })
        #expect(displays.map(\.id) == [2])
        #expect(lines.count == 1 && lines[0].contains("Display 2"))
    }

    @Test func aSubscriberWhoseWatchEndsIsDropped() async throws {
        let suite = "app.zivlet.tests.notch-latch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = ScreenGeometryReader(defaults: defaults, screens: { [Self.external] })
        let stream = reader.changes
        let watch = Task { for await _ in stream {} }
        #expect(reader.subscriberCount == 1)
        watch.cancel()
        #expect(await eventually { reader.subscriberCount == 0 })
        reader.reload()  // nothing left to yield into
        #expect(reader.subscriberCount == 0)
    }

    @Test func theNotchLatchIsStoredAndSurvivesTheLidClosing() throws {
        let suite = "app.zivlet.tests.notch-latch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let open = ScreenGeometryReader(defaults: defaults, screens: { [Self.recorded] })
        #expect(open.hasBuiltInNotch && defaults.bool(forKey: ScreenGeometryReader.latchKey))
        let closed = ScreenGeometryReader(defaults: defaults, screens: { [Self.external] })
        #expect(closed.hasBuiltInNotch && closed.displays.map(\.id) == [2])
    }

    @Test func aMacWithoutANotchNeverLatches() throws {
        let suite = "app.zivlet.tests.notch-latch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!ScreenGeometryReader(defaults: defaults, screens: { [Self.external] }).hasBuiltInNotch)
    }

    @Test func aScreenChangeIsReadAgainAndFannedOut() async throws {
        let suite = "app.zivlet.tests.notch-latch.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = RawScreens([Self.external])
        let reader = ScreenGeometryReader(defaults: defaults, screens: { source.raws })
        let first = reader.changes
        let second = reader.changes
        source.raws = [Self.recorded, Self.external]
        reader.reload()
        var a = first.makeAsyncIterator()
        var b = second.makeAsyncIterator()
        #expect(await a.next()?.map(\.id) == [1, 2])
        #expect(await b.next()?.map(\.id) == [1, 2])
        #expect(reader.hasBuiltInNotch)
    }

    @Test func theLiveScreensMapWithoutErrors() {
        let suite = "app.zivlet.tests.notch-live.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = ScreenGeometryReader(defaults: defaults)
        #expect(reader.displays.count == NSScreen.screens.count)
    }
}

/// Screens the test changes between reads.
@MainActor
final class RawScreens {
    var raws: [ScreenGeometryReader.Raw]
    init(_ raws: [ScreenGeometryReader.Raw]) { self.raws = raws }
}
