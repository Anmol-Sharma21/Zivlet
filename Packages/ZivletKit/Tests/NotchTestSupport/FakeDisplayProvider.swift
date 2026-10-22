import ZivletNotch
import ZivletNotchCore

/// A display provider for shell tests: displays are set by the test and every subscriber sees each change.
@MainActor
public final class FakeDisplayProvider: DisplayGeometryProvider {
    public private(set) var displays: [DisplayGeometry]
    public var hasBuiltInNotch: Bool
    private var subscribers: [Int: AsyncStream<[DisplayGeometry]>.Continuation] = [:]
    private var nextID = 0

    public init(_ displays: [DisplayGeometry], hasBuiltInNotch: Bool = true) {
        self.displays = displays
        self.hasBuiltInNotch = hasBuiltInNotch
    }

    public var changes: AsyncStream<[DisplayGeometry]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [DisplayGeometry].self)
        subscribers[nextID] = continuation
        nextID += 1
        return stream
    }

    public func set(_ displays: [DisplayGeometry]) {
        self.displays = displays
        for continuation in subscribers.values { continuation.yield(displays) }
    }

    /// The recorded notch display and a plain 1080p one, both far from every real screen: ids 1 and 2.
    public static func notchAndExternal() throws -> FakeDisplayProvider {
        FakeDisplayProvider([try OffscreenDisplays.notch(), try OffscreenDisplays.plain()])
    }

    public static func notchOnly() throws -> FakeDisplayProvider {
        FakeDisplayProvider([try OffscreenDisplays.notch()])
    }
}

/// The fixtures moved off every real screen: the notch display at (−5000, −5000), the plain one at x −7000.
public enum OffscreenDisplays {
    public static func notch() throws -> DisplayGeometry {
        try DisplayFixtures.moved(try DisplayFixtures.mbp14MoreSpace(), dx: -5_000, dy: -5_000)
    }

    public static func plain() throws -> DisplayGeometry {
        try DisplayFixtures.moved(try DisplayFixtures.noNotch1080(), dx: -5_080, dy: 0)
    }
}
