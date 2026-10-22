import ZivletNotchCore

/// Where the island learns about displays (design/19 §3.2). `ScreenGeometryReader` in the app, a fake in tests.
public protocol DisplayGeometryProvider: AnyObject {
    /// The menu-bar display first.
    var displays: [DisplayGeometry] { get }
    /// A new stream per call; every subscriber gets each change (the same fan-out as `SettingsStore.changes`).
    var changes: AsyncStream<[DisplayGeometry]> { get }
    /// True once this Mac has shown a built-in display with a housing; never false again (D-M5a-11).
    var hasBuiltInNotch: Bool { get }
}
