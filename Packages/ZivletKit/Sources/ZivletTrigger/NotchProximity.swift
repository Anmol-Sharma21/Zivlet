import Foundation
import ZivletCore

/// What the proximity rule reports to the tray: a file drag came to rest at a notch, or left it again.
public enum NotchProximityEvent: Sendable, Equatable, Codable {
    case entered(display: UInt32)
    case left(display: UInt32)
}

/// "A file drag is resting at the notch" (P2-143, D-M5b-9), from the live samples the trigger host already takes, so
/// it needs no permission. It enters when the pointer has stayed inside one zone, at or under `maxSpeed` between
/// consecutive samples, for `dwell`; a faster sample or a step out of the zone restarts the clock. Once entered it
/// leaves only when the pointer is more than `release` outside that zone, so the open drop target does not flicker.
/// Pure and immutable: every observation returns a new value.
public struct NotchProximity: Sendable, Equatable {
    /// The constants live here and nowhere else, so recorded drags (OS-M5b-1) change numbers, not code.
    public struct Config: Sendable, Equatable {
        /// Points added on each side of the housing (or the pill) by the zone builder.
        public let margin: Double
        public let dwell: Duration
        /// Points per second; nil means no speed limit (the tuning grid's "none").
        public let maxSpeed: Double?
        /// How far outside the zone the pointer may slip once entered.
        public let release: Double

        public init(margin: Double, dwell: Duration, maxSpeed: Double?, release: Double) {
            self.margin = margin
            self.dwell = dwell
            self.maxSpeed = maxSpeed
            self.release = release
        }

        /// From a synthetic grid search (plan 16 §3.6); a starting point until the owner's recordings decide.
        public static let provisional = Config(
            margin: 40, dwell: .milliseconds(100), maxSpeed: 800, release: 24)
    }

    /// One display's zone, in global points with y up, the margin already applied.
    public struct Zone: Sendable, Equatable, Codable {
        public let display: UInt32
        public let rect: Rect2D

        public init(display: UInt32, rect: Rect2D) {
            self.display = display
            self.rect = rect
        }
    }

    public let zones: [Zone]
    public let config: Config
    /// The display whose zone the drag is resting in, once entered.
    public let entered: UInt32?
    private let dwellingSince: Dwell?
    private let last: Fix?

    public init(zones: [Zone], config: Config = .provisional) {
        self.init(zones: zones, config: config, entered: nil, dwellingSince: nil, last: nil)
    }

    private init(zones: [Zone], config: Config, entered: UInt32?, dwellingSince: Dwell?, last: Fix?) {
        self.zones = zones
        self.config = config
        self.entered = entered
        self.dwellingSince = dwellingSince
        self.last = last
    }

    /// The rule after `sample`, and the event this sample caused, if any.
    public func observing(_ sample: InputSample) -> (NotchProximity, NotchProximityEvent?) {
        let fix = Fix(uptime: sample.uptime, location: sample.location)
        if let last, fix.uptime <= last.uptime { return (self, nil) }
        if let entered { return observingWhileEntered(entered, fix) }
        let zone = zones.first { $0.rect.contains(fix.location) }
        guard let zone, isSlow(fix) else { return (with(entered: nil, dwell: nil, last: fix), nil) }
        let dwell =
            dwellingSince.flatMap { $0.display == zone.display ? $0 : nil }
            ?? Dwell(display: zone.display, since: fix.uptime)
        guard fix.uptime - dwell.since >= config.dwell else {
            return (with(entered: nil, dwell: dwell, last: fix), nil)
        }
        return (with(entered: zone.display, dwell: nil, last: fix), .entered(display: zone.display))
    }

    /// The drag ended: nothing entered, no dwell, no last sample. The zones stay.
    public func reset() -> NotchProximity {
        NotchProximity(zones: zones, config: config)
    }

    /// The displays changed: new zones, and the rest forgotten as at the end of a drag.
    public func replacingZones(_ zones: [Zone]) -> NotchProximity {
        NotchProximity(zones: zones, config: config)
    }

    /// The events `samples` cause, fed in order from this state.
    public func events(for samples: [InputSample]) -> [NotchProximityEvent] {
        var proximity = self
        var events: [NotchProximityEvent] = []
        for sample in samples {
            let (next, event) = proximity.observing(sample)
            if let event { events.append(event) }
            proximity = next
        }
        return events
    }

    /// The state after `samples`, fed in order from this state.
    public func feeding(_ samples: [InputSample]) -> NotchProximity {
        samples.reduce(self) { $0.observing($1).0 }
    }

    // MARK: - Private

    private func observingWhileEntered(_ display: UInt32, _ fix: Fix) -> (NotchProximity, NotchProximityEvent?) {
        guard let zone = zones.first(where: { $0.display == display }),
            zone.rect.distance(to: fix.location) <= config.release
        else { return (with(entered: nil, dwell: nil, last: fix), .left(display: display)) }
        return (with(entered: display, dwell: nil, last: fix), nil)
    }

    private func isSlow(_ fix: Fix) -> Bool {
        guard let maxSpeed = config.maxSpeed, let last else { return true }
        let seconds = Self.seconds(fix.uptime - last.uptime)
        let distance = hypot(fix.location.x - last.location.x, fix.location.y - last.location.y)
        return distance / seconds <= maxSpeed
    }

    private func with(entered: UInt32?, dwell: Dwell?, last: Fix) -> NotchProximity {
        NotchProximity(zones: zones, config: config, entered: entered, dwellingSince: dwell, last: last)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
    }
}

/// Where and since when the pointer has rested slowly in one zone.
private struct Dwell: Sendable, Equatable {
    let display: UInt32
    let since: Duration
}

/// The last accepted sample: its time and place.
private struct Fix: Sendable, Equatable {
    let uptime: Duration
    let location: Point2D
}

extension Rect2D {
    /// How far `point` is outside the rectangle; 0 inside or on the edge.
    func distance(to point: Point2D) -> Double {
        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return hypot(dx, dy)
    }
}
