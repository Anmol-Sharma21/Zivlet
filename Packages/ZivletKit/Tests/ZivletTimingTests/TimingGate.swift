import Foundation

/// The switch and the reporter of the timing target (D-M7-3). Unit tests never judge wall time; the suites here do,
/// and only when Scripts/timing.sh has seen the load fall to its limit and set ZIVLET_TIMING=1. Every measured value
/// is written as a `timing:` line on standard error, which the script prints with the load it was judged at.
enum TimingGate {
    static let variable = "ZIVLET_TIMING"

    /// True when the suites should run; the timing script sets the variable to "1".
    static func isEnabled(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[variable] == "1"
    }

    /// One measured value, for example `report("drop→island p95 18.2 ms of 50 ms")`.
    static func report(_ line: String) {
        FileHandle.standardError.write(Data("timing: \(line)\n".utf8))
    }

    /// A duration in milliseconds with one decimal, as the timing lines print it.
    static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let value = Double(seconds) * 1_000 + Double(attoseconds) / 1e15
        return String(format: "%.1f ms", value)
    }
}

enum TimingError: Error, Equatable {
    case noSamples
    case badPercentile(Int)
}

/// Measured durations and their nearest-rank percentiles (no interpolation, so p95 of 20 samples is the 19th).
struct Durations: Sendable {
    let sorted: [Duration]

    init(_ samples: [Duration]) {
        sorted = samples.sorted()
    }

    func percentile(_ percent: Int) throws(TimingError) -> Duration {
        guard !sorted.isEmpty else { throw .noSamples }
        guard (1...100).contains(percent) else { throw .badPercentile(percent) }
        let rank = Int((Double(percent) / 100 * Double(sorted.count)).rounded(.up))
        return sorted[rank - 1]
    }
}
