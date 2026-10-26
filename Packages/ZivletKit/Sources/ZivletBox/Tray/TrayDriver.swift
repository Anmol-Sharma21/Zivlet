import ZivletCore
import ZivletNotchCore
import ZivletTrigger

/// Turns the trigger host's live file-drag samples into the tray's proximity events and the opt-in shake (NB5, NB6,
/// D-M5b-15, D-M5b-16). It owns the two pure detectors and the wheel's state; the app only connects closures. Pause
/// stops the host, and with it everything here. While the wheel shows, samples are ignored, so neither fires; the
/// proximity rule keeps its state, so the tray opens again only on a new approach (D-M5b-8).
public final class TrayDriver {
    private let tray: TrayClient
    private let shakeToOpen: () -> Bool
    private let openForShake: (Point2D) -> Void
    /// The drag pasteboard's item count for a change count; read once per drag (D-M5b-4: no file is touched).
    private let itemCount: (Int) -> Int
    private var proximity: NotchProximity
    private var shake = ShakeDetector()
    private var wheelShowing = false
    private var counted: (changeCount: Int, items: Int)?

    public init(
        tray: TrayClient, zones: [NotchProximity.Zone], config: NotchProximity.Config = .provisional,
        shakeToOpen: @escaping () -> Bool, openForShake: @escaping (Point2D) -> Void,
        itemCount: @escaping (Int) -> Int
    ) {
        self.tray = tray
        self.shakeToOpen = shakeToOpen
        self.openForShake = openForShake
        self.itemCount = itemCount
        proximity = NotchProximity(zones: zones, config: config)
    }

    /// The tray's zone on every display, with the provisional margin (D-M5b-9).
    public static func zones(
        for displays: [DisplayGeometry], margin: Double = NotchProximity.Config.provisional.margin
    ) -> [NotchProximity.Zone] {
        displays.map { NotchProximity.Zone(display: $0.id, rect: IslandLayout.trayZone(on: $0, margin: margin)) }
    }

    /// One live sample of a file drag.
    public func observe(_ sample: InputSample) {
        guard !wheelShowing else { return }
        let (nextProximity, event) = proximity.observing(sample)
        proximity = nextProximity
        if let event { tray.proximity(event, itemCount: count(for: sample.dragChangeCount)) }
        guard shakeToOpen() else { return }
        let (nextShake, fired) = shake.observing(sample)
        shake = nextShake
        if fired { openForShake(sample.location) }
    }

    /// The drag ended: both detectors start over and the tray rests.
    public func dragEnded() {
        proximity = proximity.reset()
        shake = shake.reset()
        counted = nil
        tray.dragEnded()
    }

    public func wheelShown() {
        wheelShowing = true
        tray.wheelShown()
    }

    /// The wheel hid at `uptime` (the samples' clock): the shake waits out its cooldown.
    public func wheelHidden(at uptime: Duration) {
        wheelShowing = false
        shake = shake.wheelHidden(at: uptime)
        tray.wheelHidden()
    }

    /// The displays changed: new zones, and the proximity rule starts over.
    public func zonesChanged(_ zones: [NotchProximity.Zone]) {
        proximity = proximity.replacingZones(zones)
    }

    private func count(for changeCount: Int) -> Int {
        if let counted, counted.changeCount == changeCount { return counted.items }
        let items = itemCount(changeCount)
        counted = (changeCount, items)
        return items
    }
}
