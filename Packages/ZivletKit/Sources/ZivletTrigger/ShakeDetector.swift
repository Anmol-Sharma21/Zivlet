import ZivletCore

/// Shake to open the Drop Box (P2-141, D-M5b-15, opt-in): during a live file drag, `reversals` horizontal changes
/// of direction, each a swing of at least `minAmplitude` from the last turning point, inside `window`. It fires
/// once and stays latched until `reset()` (the drag ended). For `cooldown` after the wheel hides, reversals are
/// not counted, and the ones before it are forgotten. Pure: the host feeds it the live samples it already takes.
public struct ShakeDetector: Sendable, Equatable {
    public struct Config: Sendable, Equatable {
        public var reversals = 4
        public var minAmplitude = 30.0
        public var window = Duration.milliseconds(600)
        public var cooldown = Duration.milliseconds(300)

        public init() {}
    }

    public let config: Config
    public let hasFired: Bool
    private let swing: Swing
    private let reversalTimes: [Duration]
    private let blockedUntil: Duration?

    public init(config: Config = Config()) {
        self.init(config: config, hasFired: false, swing: Swing(), reversalTimes: [], blockedUntil: nil)
    }

    private init(config: Config, hasFired: Bool, swing: Swing, reversalTimes: [Duration], blockedUntil: Duration?) {
        self.config = config
        self.hasFired = hasFired
        self.swing = swing
        self.reversalTimes = reversalTimes
        self.blockedUntil = blockedUntil
    }

    /// The detector after `sample`, and whether this sample completed a shake.
    public func observing(_ sample: InputSample) -> (ShakeDetector, fired: Bool) {
        guard !hasFired else { return (self, false) }
        let now = sample.uptime
        let (nextSwing, reversed) = swing.next(sample.location.x, minAmplitude: config.minAmplitude)
        let blocked = blockedUntil.map { now < $0 } ?? false
        let times = (reversed && !blocked ? reversalTimes + [now] : reversalTimes).filter { now - $0 <= config.window }
        let fired = times.count >= config.reversals
        let next = ShakeDetector(
            config: config, hasFired: fired, swing: nextSwing, reversalTimes: times, blockedUntil: blockedUntil)
        return (next, fired)
    }

    /// The wheel just hid at `uptime`: forget earlier reversals and count none for `cooldown`.
    public func wheelHidden(at uptime: Duration) -> ShakeDetector {
        ShakeDetector(
            config: config, hasFired: hasFired, swing: swing, reversalTimes: [], blockedUntil: uptime + config.cooldown)
    }

    /// A new drag: unlatched and without history; a running cooldown still applies.
    public func reset() -> ShakeDetector {
        ShakeDetector(config: config, hasFired: false, swing: Swing(), reversalTimes: [], blockedUntil: blockedUntil)
    }

    /// Whether `samples`, fed in order from this state, fire.
    public func fires(on samples: [InputSample]) -> Bool {
        var detector = self
        for sample in samples {
            let (next, fired) = detector.observing(sample)
            if fired { return true }
            detector = next
        }
        return false
    }

    public static func fires(on samples: [InputSample], config: Config = Config()) -> Bool {
        ShakeDetector(config: config).fires(on: samples)
    }
}

/// The horizontal movement since the last turning point. Until the first swing of `minAmplitude` the direction is
/// open and the range seen so far is kept, so a shake that starts against the approach is not missed.
private struct Swing: Sendable, Equatable {
    var low = Double.infinity
    var high = -Double.infinity
    /// +1 right, −1 left, 0 not decided yet.
    var direction = 0
    var extreme = 0.0

    func next(_ x: Double, minAmplitude: Double) -> (Swing, reversed: Bool) {
        var copy = self
        guard direction != 0 else {
            copy.low = min(low, x)
            copy.high = max(high, x)
            if x - copy.low >= minAmplitude { copy.direction = 1 }
            if copy.high - x >= minAmplitude { copy.direction = -1 }
            copy.extreme = x
            return (copy, false)
        }
        let travel = (x - extreme) * Double(direction)
        if travel > 0 {
            copy.extreme = x
            return (copy, false)
        }
        guard -travel >= minAmplitude else { return (self, false) }
        copy.direction = -direction
        copy.extreme = x
        return (copy, true)
    }
}
