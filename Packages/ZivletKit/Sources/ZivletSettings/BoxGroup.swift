/// When box items leave on their own (17e §2.3). Its own enum: Settings does not depend on the shelf module; the
/// app maps it to `AutoClear`.
public enum BoxAutoClearChoice: String, Sendable, Codable, CaseIterable {
    case off, afterLeaving, after24Hours
}

/// Where a drop on the BOX slice or the tray goes (OWN-APP-1): the most recent box, or a new one.
public enum BoxDropsChoice: String, Sendable, Codable, CaseIterable {
    case recentBox, newBox
}

/// Drop Box group (D-M5b-19): stored as `settings.box.v1`. The tray shows while dragging near the notch; shake to
/// open is opt-in; nothing clears on its own; drops go to the most recent box. No names or paths, so Copy
/// Diagnostics lists it as it is.
public struct BoxGroup: Sendable, Equatable, Codable {
    public var trayWhileDragging = true
    public var shakeToOpen = false
    public var autoClear = BoxAutoClearChoice.off
    public var dropsGo = BoxDropsChoice.recentBox

    public init() {}
}
