import os

/// One signpost interval the HUD began; `state` is nil when nothing was sent to the system.
struct HUDSignpostInterval {
    let name: StaticString
    let state: OSSignpostIntervalState?
}

/// The HUD's signpost intervals (`drop→island`, which X2 reads from the log); a seam so a test can see each interval
/// begun and ended once (D-M7-4).
protocol HUDSignposting {
    func begin(_ name: StaticString) -> HUDSignpostInterval
    func end(_ interval: HUDSignpostInterval)
}

/// The production intervals: the `hud` category of the app's subsystem.
struct OSHUDSignposts: HUDSignposting {
    private let signposter = OSSignposter(subsystem: "app.zivlet.Zivlet", category: "hud")

    func begin(_ name: StaticString) -> HUDSignpostInterval {
        HUDSignpostInterval(name: name, state: signposter.beginInterval(name))
    }

    func end(_ interval: HUDSignpostInterval) {
        guard let state = interval.state else { return }
        signposter.endInterval(interval.name, state)
    }
}
