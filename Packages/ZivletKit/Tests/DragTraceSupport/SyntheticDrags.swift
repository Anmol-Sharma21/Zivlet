import Foundation
import TestSupport
import ZivletCore
import ZivletTrigger

/// Made-up file drags for the shake and proximity tests (D-M5b-15, P2-197), seeded so every run is the same. Paths
/// are minimum-jerk moves sampled at 120 Hz in a 1800 × 1169 pt display; none of this is a recording, so the
/// numbers they give are a starting point only.
public enum SyntheticDrags {
    public static let rate = 120.0
    public static let display = Rect2D(x: 0, y: 0, width: 1800, height: 1169)

    /// The ordinary drags a shake detector must ignore.
    public enum NonShake: String, CaseIterable, Sendable {
        case straight, curved, hesitateAndCorrect, wiggle1Hz, tremor8Hz
    }

    /// A short approach, then a horizontal shake of 4–6 half-cycles at 3–6 Hz and ± 40–120 pt, then a short hold.
    public static func shake(_ rng: inout SplitMix64) -> [InputSample] {
        let start = point(in: display.insetBy(200), &rng)
        let approach = rng.double(in: 50...300)
        let angle = rng.double(in: 0...(2 * .pi))
        let center = Point2D(x: start.x + approach * cos(angle), y: start.y + approach * sin(angle))
        let lead = minimumJerk(from: start, to: center, seconds: rng.double(in: 0.10...0.25))
        let frequency = rng.double(in: 3...6)
        let amplitude = rng.double(in: 40...120) * (rng.next() % 2 == 0 ? 1 : -1)
        let halfCycles = Double(Int.random(in: 4...6, using: &rng))
        let drift = rng.double(in: -10...10)
        let shaking = path(seconds: halfCycles / (2 * frequency)) { t, _ in
            Point2D(
                x: center.x + amplitude * sin(2 * .pi * frequency * t),
                y: center.y + drift * t * frequency)
        }
        let end = shaking.last ?? center
        return samples(from: lead + shaking + hold(at: end, seconds: rng.double(in: 0.05...0.15)))
    }

    public static func trace(_ kind: NonShake, _ rng: inout SplitMix64) -> [InputSample] {
        switch kind {
        case .straight: samples(from: straight(&rng))
        case .curved: samples(from: curved(&rng))
        case .hesitateAndCorrect: samples(from: hesitateAndCorrect(&rng))
        case .wiggle1Hz: samples(from: wiggle(&rng))
        case .tremor8Hz: samples(from: tremor(&rng))
        }
    }

    // MARK: - Kinds

    private static func straight(_ rng: inout SplitMix64) -> [Point2D] {
        let (from, to) = endpoints(&rng)
        let move = minimumJerk(from: from, to: to, seconds: rng.double(in: 0.3...1.2))
        return jittered(move + hold(at: to, seconds: 0.1), &rng)
    }

    private static func curved(_ rng: inout SplitMix64) -> [Point2D] {
        let (from, to) = endpoints(&rng)
        let bend = rng.double(in: 0.2...0.5) * (rng.next() % 2 == 0 ? 1 : -1)
        let control = Point2D(
            x: (from.x + to.x) / 2 - (to.y - from.y) * bend, y: (from.y + to.y) / 2 + (to.x - from.x) * bend)
        let move = path(seconds: rng.double(in: 0.4...1.2)) { _, progress in
            let s = jerk(progress)
            let a = (1 - s) * (1 - s)
            let b = 2 * (1 - s) * s
            let c = s * s
            return Point2D(x: a * from.x + b * control.x + c * to.x, y: a * from.y + b * control.y + c * to.y)
        }
        return jittered(move + hold(at: to, seconds: 0.1), &rng)
    }

    /// Past the target by 20–60 pt, a pause, back to the target, sometimes a second small correction.
    private static func hesitateAndCorrect(_ rng: inout SplitMix64) -> [Point2D] {
        let (from, to) = endpoints(&rng)
        let length = max(hypot(to.x - from.x, to.y - from.y), 1)
        let over = rng.double(in: 20...60)
        let past = Point2D(x: to.x + (to.x - from.x) / length * over, y: to.y + (to.y - from.y) / length * over)
        let back = Point2D(x: to.x - (to.x - from.x) / length * 8, y: to.y - (to.y - from.y) / length * 8)
        var points = minimumJerk(from: from, to: past, seconds: rng.double(in: 0.3...0.9))
        points += hold(at: past, seconds: rng.double(in: 0.1...0.3))
        points += minimumJerk(from: past, to: back, seconds: rng.double(in: 0.15...0.3))
        points += minimumJerk(from: back, to: to, seconds: 0.12) + hold(at: to, seconds: 0.1)
        return jittered(points, &rng)
    }

    /// A slow side-to-side search at 1 Hz, ± 40–80 pt, for 2–3 cycles after the move.
    private static func wiggle(_ rng: inout SplitMix64) -> [Point2D] {
        let (from, to) = endpoints(&rng)
        let amplitude = rng.double(in: 40...80)
        let cycles = Double(Int.random(in: 2...3, using: &rng))
        let move = minimumJerk(from: from, to: to, seconds: rng.double(in: 0.3...0.8))
        let search = path(seconds: cycles) { t, _ in Point2D(x: to.x + amplitude * sin(2 * .pi * t), y: to.y) }
        return jittered(move + search, &rng)
    }

    /// A straight move with an 8 Hz, ± 10 pt horizontal tremor on top, held at the end.
    private static func tremor(_ rng: inout SplitMix64) -> [Point2D] {
        let (from, to) = endpoints(&rng)
        let seconds = rng.double(in: 0.4...1.2)
        let phase = rng.double(in: 0...(2 * .pi))
        let move = path(seconds: seconds + 0.6) { t, _ in
            let s = jerk(min(t / seconds, 1))
            return Point2D(
                x: from.x + (to.x - from.x) * s + 10 * sin(2 * .pi * 8 * t + phase), y: from.y + (to.y - from.y) * s)
        }
        return move
    }

    // MARK: - Building blocks

    private static func endpoints(_ rng: inout SplitMix64) -> (Point2D, Point2D) {
        let from = point(in: display.insetBy(50), &rng)
        let distance = rng.double(in: 200...1200)
        let angle = rng.double(in: 0...(2 * .pi))
        let to = Point2D(
            x: min(max(from.x + distance * cos(angle), 20), display.maxX - 20),
            y: min(max(from.y + distance * sin(angle), 20), display.maxY - 20))
        return (from, to)
    }

    private static func point(in rect: Rect2D, _ rng: inout SplitMix64) -> Point2D {
        Point2D(x: rng.double(in: rect.minX...rect.maxX), y: rng.double(in: rect.minY...rect.maxY))
    }

    /// 10τ³ − 15τ⁴ + 6τ⁵: the smooth start and stop of an aimed hand movement.
    static func jerk(_ tau: Double) -> Double { tau * tau * tau * (10 - 15 * tau + 6 * tau * tau) }

    static func minimumJerk(from: Point2D, to: Point2D, seconds: Double) -> [Point2D] {
        path(seconds: seconds) { _, progress in
            let s = jerk(progress)
            return Point2D(x: from.x + (to.x - from.x) * s, y: from.y + (to.y - from.y) * s)
        }
    }

    static func hold(at point: Point2D, seconds: Double) -> [Point2D] {
        Array(repeating: point, count: max(Int(seconds * rate), 1))
    }

    /// One point per frame over `seconds`; the closure gets the time and the progress 0…1.
    static func path(seconds: Double, _ position: (Double, Double) -> Point2D) -> [Point2D] {
        let frames = max(Int(seconds * rate), 1)
        return (0...frames).map { frame in
            let t = Double(frame) / rate
            return position(t, Double(frame) / Double(frames))
        }
    }

    /// ± 1 pt of sensor noise.
    private static func jittered(_ points: [Point2D], _ rng: inout SplitMix64) -> [Point2D] {
        points.map { Point2D(x: $0.x + rng.double(in: -1...1), y: $0.y + rng.double(in: -1...1)) }
    }

    /// Frame samples of a live file drag, one per point at 120 Hz, from an uptime of 1 s.
    public static func samples(from points: [Point2D]) -> [InputSample] {
        points.enumerated().map { index, point in
            InputSample(
                uptime: .seconds(1) + .nanoseconds(Int64(Double(index) / rate * 1e9)), source: .frame,
                primaryButtonDown: true, dragChangeCount: 1, dragHasFileTypes: true, location: point)
        }
    }
}

extension SplitMix64 {
    mutating func double(in range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }
}

extension Rect2D {
    func insetBy(_ inset: Double) -> Rect2D {
        Rect2D(x: x + inset, y: y + inset, width: width - 2 * inset, height: height - 2 * inset)
    }
}
