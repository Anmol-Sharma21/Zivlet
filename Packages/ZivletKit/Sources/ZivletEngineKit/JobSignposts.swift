import ZivletCore
import os

/// `OSSignposter` intervals for one job's stages (P1-48, 10 §8.7): `probe` and `plan` inside the engines, `execute`,
/// `verify` and `publish` in the pipeline, plus `drop→admit` in the conversion service. Visible in Instruments
/// (Logging, Points of Interest) and `log stream --signpost`; names only, never paths.
public enum JobSignposts {
    public static let signposter = OSSignposter(subsystem: "app.zivlet.Zivlet", category: "scheduler")

    public static func interval<T>(_ name: StaticString, _ body: () async throws(JobError) -> T)
        async throws(JobError) -> T
    {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try await body()
    }

    public static func interval<T>(_ name: StaticString, _ body: () throws(JobError) -> T) throws(JobError) -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}
