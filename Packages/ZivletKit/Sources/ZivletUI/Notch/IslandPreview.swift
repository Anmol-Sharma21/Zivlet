import Foundation
import ZivletCore
import ZivletRuntime

// Debug builds only: Release must not show made-up jobs.
#if DEBUG
    /// `-ZivletIslandPreview <state>` puts one made-up job on the Notch HUD without a drop or a conversion, for the
    /// demo screenshots and the idle-CPU row of the exit runner (plan 12b N13): a job resting at 40 %, a job whose
    /// progress changes ten times a second, a job of unknown length, the working card opened, a saved result and a
    /// failure (each shown as its toast, then opened as its card).
    public enum IslandPreview: String, CaseIterable, Sendable {
        case collapsed, progress, indeterminate, expanded, result, failure

        public enum Invalid: Error, Equatable {
            case missingValue
            case unknown(String)
        }

        public static let flag = "-ZivletIslandPreview"
        /// Progress per tick of `.progress`: 0.2 % every 100 ms, wrapping at 100 %.
        static let stepFraction = 0.002
        static let restingFraction = 0.4

        /// Nil when the flag is absent.
        public static func parse(arguments: [String]) throws(Invalid) -> IslandPreview? {
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            guard arguments.indices.contains(index + 1) else { throw .missingValue }
            let value = arguments[index + 1]
            guard let preview = IslandPreview(rawValue: value) else { throw .unknown(value) }
            return preview
        }

        /// The demo opens the island after showing the snapshot: the working, result or failure card.
        public var opens: Bool { self == .expanded || self == .result || self == .failure }

        /// How often `.progress` sends a new snapshot (the 10 Hz input of D-N7); nil for the still states.
        public var tick: Duration? { self == .progress ? .milliseconds(100) : nil }

        /// The snapshot the preview starts with.
        public func first() throws -> BatchSnapshot {
            switch self {
            case .collapsed, .expanded: try Self.running(JobProgress(fraction: Self.restingFraction, eta: .seconds(12)))
            case .progress: try Self.running(JobProgress(fraction: 0, eta: .seconds(50)))
            case .indeterminate: try Self.running(JobProgress(fraction: nil, bytesWritten: 3_400_000))
            case .result: try Self.saved()
            case .failure: try Self.failed()
            }
        }

        /// `.progress` after `step` ticks: the same batch, the fraction moved on.
        public func advanced(_ snapshot: BatchSnapshot, step: Int) throws -> BatchSnapshot {
            guard let job = snapshot.items.first?.job else { return snapshot }
            let fraction = (Double(step) * Self.stepFraction).truncatingRemainder(dividingBy: 1)
            let progress = JobProgress(fraction: fraction, eta: .seconds(Int64((1 - fraction) * 50)))
            return snapshot.applying(.changed(snapshot.batch, job, .running(progress)))
        }

        private static func request(_ name: String, from format: FormatID, to target: FormatID) throws -> JobRequest {
            let input = try InputItem(
                url: URL(filePath: "/tmp/\(name)"), format: format, byteCount: 2_100_000)
            return try JobRequest(input: input, operation: .convert(target), destination: URL(filePath: "/tmp"))
        }

        private static func running(_ progress: JobProgress) throws -> BatchSnapshot {
            let request = try request("holiday.mov", from: .mov, to: .mp4)
            let batch = BatchID()
            return BatchSnapshot(batch: batch, target: .mp4, plan: RequestPlan(requests: [request], rejections: []))
                .applying(.changed(batch, request.id, .running(progress)))
        }

        private static func saved() throws -> BatchSnapshot {
            let request = try request("photo.heic", from: .heic, to: .jpg)
            let batch = BatchID()
            let output = PublishedOutput(
                url: URL(filePath: "/tmp/photo.jpg"), format: .jpg, byteCount: 640_000, fileID: 1, modified: Date())
            return BatchSnapshot(batch: batch, target: .jpg, plan: RequestPlan(requests: [request], rejections: []))
                .applying(.changed(batch, request.id, .succeeded(output))).applying(.finished(batch))
        }

        private static func failed() throws -> BatchSnapshot {
            let request = try request("holiday.mov", from: .mov, to: .mp4)
            let batch = BatchID()
            return BatchSnapshot(batch: batch, target: .mp4, plan: RequestPlan(requests: [request], rejections: []))
                .applying(.changed(batch, request.id, .failed(.diskFull))).applying(.finished(batch))
        }
    }
#endif
