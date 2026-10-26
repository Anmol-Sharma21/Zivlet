import ZivletCore
import ZivletTrigger

/// Hand-made live samples for table tests: a pointer at rest, a straight line at a steady speed.
public enum Samples {
    /// A pointer held still at `point` from `start` for `duration`, one sample per `1/hz` s, both ends included.
    public static func rest(at point: Point2D, from start: Duration, for duration: Duration, hz: Double = 120)
        -> [InputSample]
    {
        line(from: point, to: point, starting: start, over: duration, hz: hz)
    }

    /// A straight move at a steady speed from `from` to `to` over `duration`, both ends included.
    public static func line(
        from: Point2D, to: Point2D, starting start: Duration = .seconds(1), over duration: Duration, hz: Double = 120
    ) -> [InputSample] {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) * 1e-18
        let steps = max(Int((seconds * hz).rounded()), 1)
        return (0...steps).map { step in
            let progress = Double(step) / Double(steps)
            let point = Point2D(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
            return sample(at: point, uptime: start + duration * progress)
        }
    }

    /// One live file-drag sample.
    public static func sample(at point: Point2D, uptime: Duration) -> InputSample {
        InputSample(
            uptime: uptime, source: .frame, primaryButtonDown: true, dragChangeCount: 1, dragHasFileTypes: true,
            location: point)
    }
}
