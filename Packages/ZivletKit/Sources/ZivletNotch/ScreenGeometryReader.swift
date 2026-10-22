import AppKit
import ZivletCore
import ZivletNotchCore
import os

/// The live `DisplayGeometryProvider` (design/19 §3.2): `NSScreen.screens` as plain values, read again on every
/// screen-parameter change and fanned out to every subscriber. `hasBuiltInNotch` is a latch kept in the injected
/// defaults, so closing the lid does not change "Automatic" (D-M5a-11).
public final class ScreenGeometryReader: DisplayGeometryProvider {
    /// One screen's values as AppKit reports them; the mapping to `DisplayGeometry` is a pure function of these.
    public struct Raw: Sendable, Equatable {
        public let number: UInt32
        public let frame: CGRect
        public let visible: CGRect
        public let safeTop: Double
        public let left: CGRect?
        public let right: CGRect?
        public let builtIn: Bool

        public init(
            number: UInt32, frame: CGRect, visible: CGRect, safeTop: Double, left: CGRect?, right: CGRect?,
            builtIn: Bool
        ) {
            self.number = number
            self.frame = frame
            self.visible = visible
            self.safeTop = safeTop
            self.left = left
            self.right = right
            self.builtIn = builtIn
        }
    }

    public static let latchKey = "notch.builtInSeen.v1"

    public private(set) var displays: [DisplayGeometry] = []
    public private(set) var hasBuiltInNotch: Bool
    private let defaults: UserDefaults
    private let screens: @MainActor () -> [Raw]
    private var subscribers: [Int: AsyncStream<[DisplayGeometry]>.Continuation] = [:]
    private var nextSubscriber = 0
    private var observer: (any NSObjectProtocol)?
    private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "hud")

    public init(defaults: UserDefaults = .standard, screens: @escaping @MainActor () -> [Raw] = { live() }) {
        self.defaults = defaults
        self.screens = screens
        hasBuiltInNotch = defaults.bool(forKey: Self.latchKey)
        read()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.reload() } }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        for continuation in subscribers.values { continuation.finish() }
    }

    public var changes: AsyncStream<[DisplayGeometry]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [DisplayGeometry].self)
        subscribers[nextSubscriber] = continuation
        nextSubscriber += 1
        return stream
    }

    /// Reads the screens again and tells every subscriber.
    public func reload() {
        read()
        for continuation in subscribers.values { continuation.yield(displays) }
    }

    private func read() {
        displays = Self.geometries(screens()) { Self.logger.error("\($0, privacy: .public)") }
        let seen = NotchGeometry.builtInNotchSeen(before: hasBuiltInNotch, displays: displays)
        if seen && !hasBuiltInNotch { defaults.set(true, forKey: Self.latchKey) }
        hasBuiltInNotch = seen
    }

    /// Every valid screen, in order; each invalid one is skipped with one line to `log` (no names, no paths).
    public static func geometries(_ raws: [Raw], log: (String) -> Void) -> [DisplayGeometry] {
        raws.compactMap { geometry($0, log: log) }
    }

    public static func geometry(_ raw: Raw, log: (String) -> Void) -> DisplayGeometry? {
        do {
            return try DisplayGeometry(
                id: raw.number, frame: Rect2D(raw.frame), visibleFrame: Rect2D(raw.visible), safeAreaTop: raw.safeTop,
                auxiliaryTopLeft: global(raw.left, in: raw.frame), auxiliaryTopRight: global(raw.right, in: raw.frame),
                isBuiltIn: raw.builtIn)
        } catch {
            log("Display \(raw.number) skipped: \(error)")
            return nil
        }
    }

    /// AppKit's auxiliary areas are taken as global when they lie inside the screen's frame, else as relative to its
    /// origin, so a notch display that is not at the origin still finds its housing.
    static func global(_ rect: CGRect?, in frame: CGRect) -> Rect2D? {
        guard let rect else { return nil }
        if frame.contains(rect) { return Rect2D(rect) }
        return Rect2D(rect.offsetBy(dx: frame.minX, dy: frame.minY))
    }

    public static func live() -> [Raw] {
        NSScreen.screens.map { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            let number = (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
            return Raw(
                number: number, frame: screen.frame, visible: screen.visibleFrame, safeTop: screen.safeAreaInsets.top,
                left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea,
                builtIn: CGDisplayIsBuiltin(number) != 0)
        }
    }
}
