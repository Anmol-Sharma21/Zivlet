import Foundation
import TestSupport
import ZivletCore
import ZivletTrigger

/// Made-up drags for the proximity replay (P2-197, plan 16 §3.6), for any display. Aimed moves are minimum-jerk
/// paths at 120 Hz with ± 1 pt of tremor, an overshoot and a correction in 3 of 10, and a pause before the drop.
/// None of this is a recording: the numbers it gives are a starting point until the owner records real drags.
extension SyntheticDrags {
    /// Where notch-bound drags end around the zone's centre.
    public enum Spread: Sendable, CaseIterable {
        /// Normal, SD 50 pt (Fitts-like aiming).
        case gaussian50
        /// Uniform ± 150 pt (pessimistic).
        case uniform150
    }

    /// Everyday drags that must not open the tray, with their share of 200.
    public enum NormalKind: String, Sendable, CaseIterable {
        /// Anywhere on the display (120 of 200).
        case anywhere
        /// Just under the menu bar, near the centre: the hard case (40 of 200).
        case underMenuBar
        /// Onto the menu bar beside the zone, as onto a status item (20 of 200).
        case besideZone
        /// Into the Dock (20 of 200).
        case dock

        var shareOf200: Int {
            switch self {
            case .anywhere: 120
            case .underMenuBar: 40
            case .besideZone, .dock: 20
            }
        }
    }

    /// `normal` everyday drags (in the 120/40/20/20 mix) and `notchBound` drags aimed at the zone, from one seed.
    public static func proximitySet(
        on display: TraceDisplay, seed: UInt64, normal: Int = 200, notchBound: Int = 50, spread: Spread = .gaussian50
    ) throws -> [DragTrace] {
        var rng = SplitMix64(seed: seed)
        let kinds = NormalKind.allCases.flatMap { kind in
            Array(repeating: kind, count: kind.shareOf200 * normal / 200)
        }
        let everyday = try kinds.map { try normalDrag($0, on: display, &rng) }
        let aimed = try (0..<notchBound).map { _ in try self.notchBound(on: display, spread: spread, &rng) }
        return everyday + aimed
    }

    /// A drag aimed at the zone that waits there 0.12–0.6 s before the drop.
    public static func notchBound(on display: TraceDisplay, spread: Spread, _ rng: inout SplitMix64) throws
        -> DragTrace
    {
        let zone = try display.target()
        let dx: Double
        switch spread {
        case .gaussian50: dx = 50 * rng.gaussian()
        case .uniform150: dx = rng.double(in: -150...150)
        }
        let end = Point2D(x: zone.midX + dx, y: zone.maxY - abs(rng.gaussian()) * zone.height / 4)
        let start = point(in: lowerTwoThirds(of: display), &rng)
        return try trace(.notch, on: display, from: start, to: end, pause: rng.double(in: 0.12...0.6), &rng)
    }

    /// An everyday drag of `kind` with a short pause (0.03–0.15 s) before the drop.
    public static func normalDrag(_ kind: NormalKind, on display: TraceDisplay, _ rng: inout SplitMix64) throws
        -> DragTrace
    {
        let end = try normalEnd(kind, on: display, &rng)
        let start = point(in: display.visibleFrame.insetBy(50), &rng)
        return try trace(.normal, on: display, from: start, to: end, pause: rng.double(in: 0.03...0.15), &rng)
    }

    // MARK: - Ends

    private static func normalEnd(_ kind: NormalKind, on display: TraceDisplay, _ rng: inout SplitMix64) throws
        -> Point2D
    {
        let zone = try display.target()
        let visible = display.visibleFrame
        switch kind {
        case .anywhere:
            return point(in: visible.insetBy(20), &rng)
        case .underMenuBar:
            return Point2D(
                x: zone.midX + rng.double(in: -300...300), y: visible.maxY - rng.double(in: 8...120))
        case .besideZone:
            let side = rng.next() % 2 == 0 ? -1.0 : 1.0
            let away = rng.double(in: 10...400)
            let x = side < 0 ? zone.minX - away : zone.maxX + away
            return Point2D(x: x, y: display.frame.maxY - rng.double(in: 4...max(zone.height - 4, 5)))
        case .dock:
            let dock = max(visible.minY - display.frame.minY, 60)
            return Point2D(
                x: rng.double(in: visible.minX + 100...visible.maxX - 100),
                y: display.frame.minY + rng.double(in: 10...dock - 10))
        }
    }

    private static func lowerTwoThirds(of display: TraceDisplay) -> Rect2D {
        let visible = display.visibleFrame.insetBy(50)
        return Rect2D(x: visible.x, y: visible.y, width: visible.width, height: visible.height * 2 / 3)
    }

    // MARK: - Paths

    private static func trace(
        _ label: DragTrace.Label, on display: TraceDisplay, from start: Point2D, to end: Point2D, pause: Double,
        _ rng: inout SplitMix64
    ) throws -> DragTrace {
        let points = aimedMove(from: start, to: end, &rng) + hold(at: end, seconds: pause)
        let samples = points.enumerated().map { index, point in
            let clamped = clamp(jitter(point, &rng), to: display.frame)
            return DragTrace.Sample(t: 1_000 + Double(index) * 1_000 / rate, x: clamped.x, y: clamped.y, down: true)
        }
        return try DragTrace(label: label, display: display, os: "synthetic", samples: samples)
    }

    /// A Fitts-like duration for the distance; in 3 of 10 moves the hand passes the target by 3–8 % and comes back.
    private static func aimedMove(from start: Point2D, to end: Point2D, _ rng: inout SplitMix64) -> [Point2D] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let seconds = 0.25 + distance / 1_500 + rng.double(in: 0...0.2)
        guard rng.double(in: 0...1) < 0.3, distance > 1 else {
            return minimumJerk(from: start, to: end, seconds: seconds)
        }
        let over = rng.double(in: 0.03...0.08)
        let past = Point2D(x: end.x + (end.x - start.x) * over, y: end.y + (end.y - start.y) * over)
        return minimumJerk(from: start, to: past, seconds: seconds)
            + minimumJerk(from: past, to: end, seconds: rng.double(in: 0.10...0.20))
    }

    private static func jitter(_ point: Point2D, _ rng: inout SplitMix64) -> Point2D {
        Point2D(x: point.x + rng.double(in: -1...1), y: point.y + rng.double(in: -1...1))
    }

    /// The pointer cannot leave the display: it is pinned to the edges, the top edge included.
    private static func clamp(_ point: Point2D, to frame: Rect2D) -> Point2D {
        Point2D(x: min(max(point.x, frame.minX), frame.maxX), y: min(max(point.y, frame.minY), frame.maxY))
    }

    private static func point(in rect: Rect2D, _ rng: inout SplitMix64) -> Point2D {
        Point2D(x: rng.double(in: rect.minX...rect.maxX), y: rng.double(in: rect.minY...rect.maxY))
    }
}

extension SplitMix64 {
    /// A standard normal value (Box–Muller).
    mutating func gaussian() -> Double {
        let u1 = max(double(in: 0...1), 1e-12)
        let u2 = double(in: 0...1)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
