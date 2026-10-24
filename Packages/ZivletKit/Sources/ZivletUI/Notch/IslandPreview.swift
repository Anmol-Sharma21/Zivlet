import Foundation
import ZivletActions
import ZivletCore
import ZivletEngineKit
import ZivletRuntime

// Debug builds, and the optimised CPU measurement build of `make notch-idle CONFIG=release` (D-ND3): a shipped
// Release build must not show made-up jobs, and `make release-check` fails when its binary has the flag.
#if DEBUG || ZIVLET_ISLAND_PREVIEW
    /// `-ZivletIslandPreview <state>` puts made-up jobs on the Notch HUD without a drop or a conversion, for the demo
    /// screenshots and the idle-CPU rows (plan 12b N13, plan 14 D18): a job resting at 40 %, a job whose progress
    /// changes ten times a second (slowly, or fast enough to outrun the 250 ms floor), a job of unknown length, the
    /// working card opened, a saved result and a failure (each shown as its toast, then opened as its card), the same
    /// two left as toasts, an action's toast with Undo, a list of seven jobs with one failed, and since the design
    /// review the rest of 19b §5: the tab with three jobs, the failed and the done tab, an action's card with more
    /// lines than it shows, a failure with its details shown, the open card of a job of unknown length, and a result
    /// of three files with a note.
    public enum IslandPreview: String, CaseIterable, Sendable {
        case collapsed, progress, fastProgress, indeterminate, expanded, result, failure
        case savedToast, failureToast, actionToast, list
        case jobs, failedTab, doneTab, actionCard, failureDetails, indeterminateCard, resultFiles

        public enum Invalid: Error, Equatable {
            case missingValue
            case unknown(String)
            /// The state shows an action, not a batch.
            case noBatch
        }

        public static let flag = "-ZivletIslandPreview"
        /// Progress per tick of `.progress`: 0.2 % every 100 ms, wrapping at 100 %.
        static let stepFraction = 0.002
        /// Progress per tick of `.fastProgress`: 2 % every 100 ms, about 17 ring steps a second.
        static let fastStepFraction = 0.02
        static let restingFraction = 0.4

        /// Nil when the flag is absent.
        public static func parse(arguments: [String]) throws(Invalid) -> IslandPreview? {
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            guard arguments.indices.contains(index + 1) else { throw .missingValue }
            let value = arguments[index + 1]
            guard let preview = IslandPreview(rawValue: value) else { throw .unknown(value) }
            return preview
        }

        /// The demo opens the island after showing the snapshot: a card or the list.
        public var opens: Bool {
            [.expanded, .result, .failure, .list, .actionCard, .failureDetails, .indeterminateCard, .resultFiles]
                .contains(self)
        }

        /// The demo presses Show Details once the card is open.
        public var showsDetails: Bool { self == .failureDetails }

        /// How often `.progress` and `.fastProgress` send a new snapshot (the 10 Hz input of D-N7); nil otherwise.
        public var tick: Duration? { [.progress, .fastProgress].contains(self) ? .milliseconds(100) : nil }

        /// The action the state shows: a done move with Undo, or a move that left five of nine files; else nil.
        public var action: ActionResult? {
            switch self {
            case .actionToast: .done(toast: "Moved 2 files", undo: BatchID())
            case .actionCard: .partial(toast: "Moved 4 of 9 files", card: Self.partialMove, undo: BatchID())
            default: nil
            }
        }

        private static let partialMove = ActionCard(
            title: "5 files could not be moved",
            lines: (1...8).map { "scan-\($0).pdf: the destination is read-only" })

        /// The batches the state shows, in order; none for the action toast.
        public func snapshots() throws -> [BatchSnapshot] {
            switch self {
            case .collapsed, .expanded: [try Self.running(fraction: Self.restingFraction, eta: .seconds(12))]
            case .progress, .fastProgress: [try Self.running(fraction: 0, eta: .seconds(50))]
            case .indeterminate, .indeterminateCard:
                [try Self.running(JobProgress(fraction: nil, bytesWritten: 12_400_000))]
            case .result, .savedToast: [try Self.saved()]
            case .failure, .failureToast, .failedTab: [try Self.failed()]
            case .failureDetails: [try Self.failed(.processFailed(status: 1, stderrTail: Self.helperTail))]
            case .actionToast, .actionCard: []
            case .list: try Self.list()
            case .jobs: try Self.jobs()
            case .doneTab: [try Self.saved("photo"), try Self.saved("scan")]
            case .resultFiles: [try Self.savedFiles()]
            }
        }

        private static let helperTail = "Invalid data found when processing input\nConversion failed!"

        /// The first batch: the one the idle-CPU states and `.progress` move.
        public func first() throws -> BatchSnapshot {
            guard let first = try snapshots().first else { throw Invalid.noBatch }
            return first
        }

        /// `.progress` or `.fastProgress` after `step` ticks: the same batch, the fraction moved on.
        public func advanced(_ snapshot: BatchSnapshot, step: Int) throws -> BatchSnapshot {
            guard let job = snapshot.items.first?.job else { return snapshot }
            let perTick = self == .fastProgress ? Self.fastStepFraction : Self.stepFraction
            let fraction = (Double(step) * perTick).truncatingRemainder(dividingBy: 1)
            let progress = JobProgress(fraction: fraction, eta: .seconds(Int64((1 - fraction) * 50)))
            return snapshot.applying(.changed(snapshot.batch, job, .running(progress)))
        }

        private static func request(_ name: String, from format: FormatID, to target: FormatID) throws -> JobRequest {
            let input = try InputItem(
                url: URL(filePath: "/tmp/\(name)"), format: format, byteCount: 2_100_000)
            return try JobRequest(input: input, operation: .convert(target), destination: URL(filePath: "/tmp"))
        }

        private static func running(fraction: Double, eta: Duration) throws -> BatchSnapshot {
            try running(JobProgress(fraction: fraction, eta: eta))
        }

        private static func running(
            _ progress: JobProgress, name: String = "holiday.mov", from format: FormatID = .mov,
            to target: FormatID = .mp4
        ) throws -> BatchSnapshot {
            let request = try request(name, from: format, to: target)
            let batch = BatchID()
            return BatchSnapshot(batch: batch, target: target, plan: RequestPlan(requests: [request], rejections: []))
                .applying(.changed(batch, request.id, .running(progress)))
        }

        private static func saved(_ name: String = "photo") throws -> BatchSnapshot {
            let request = try request("\(name).heic", from: .heic, to: .jpg)
            let batch = BatchID()
            let output = PublishedOutput(
                url: URL(filePath: "/tmp/\(name).jpg"), format: .jpg, byteCount: 640_000, fileID: 1, modified: Date())
            return BatchSnapshot(batch: batch, target: .jpg, plan: RequestPlan(requests: [request], rejections: []))
                .applying(.changed(batch, request.id, .succeeded(output))).applying(.finished(batch))
        }

        private static func failed(_ error: JobError = .diskFull) throws -> BatchSnapshot {
            let request = try request("holiday.mov", from: .mov, to: .mp4)
            let batch = BatchID()
            return BatchSnapshot(batch: batch, target: .mp4, plan: RequestPlan(requests: [request], rejections: []))
                .applying(.changed(batch, request.id, .failed(error))).applying(.finished(batch))
        }

        /// Three JPEG pictures saved from HEIC, the first one with its transparency flattened.
        private static func savedFiles() throws -> BatchSnapshot {
            let requests = try (1...3).map { try request("shot-\($0).heic", from: .heic, to: .jpg) }
            let batch = BatchID()
            let start = BatchSnapshot(batch: batch, target: .jpg, plan: RequestPlan(requests: requests, rejections: []))
                .applying(.noted(batch, requests[0].id, [.alphaFlattened]))
            return requests.enumerated().reduce(start) { snapshot, entry in
                let output = PublishedOutput(
                    url: URL(filePath: "/tmp/shot-\(entry.offset + 1).jpg"), format: .jpg, byteCount: 480_000,
                    fileID: UInt64(entry.offset + 1), modified: Date())
                return snapshot.applying(.changed(batch, entry.element.id, .succeeded(output)))
            }.applying(.finished(batch))
        }

        /// Three jobs at once: video, audio and a document, so the tab shows "3 jobs" and their combined ring.
        private static func jobs() throws -> [BatchSnapshot] {
            [
                try running(JobProgress(fraction: 0.25, eta: .seconds(200)), name: "beach.mov"),
                try running(JobProgress(fraction: 0.6, eta: .seconds(40)), name: "interview.wav", from: .wav, to: .mp3),
                try running(JobProgress(fraction: 0.1, eta: .seconds(90)), name: "notes.md", from: .md, to: .pdf),
            ]
        }

        /// Seven jobs: one failed, four working on video, audio and a document, two saved images.
        private static func list() throws -> [BatchSnapshot] {
            [
                try running(JobProgress(fraction: 0.25, eta: .seconds(200)), name: "beach.mov"),
                try running(JobProgress(fraction: 0.6, eta: .seconds(40)), name: "interview.wav", from: .wav, to: .mp3),
                try failed(),
                try running(JobProgress(fraction: 0.1, eta: .seconds(90)), name: "notes.md", from: .md, to: .pdf),
                try running(JobProgress(fraction: nil, bytesWritten: 3_400_000), name: "talk.mkv", from: .mkv),
                try saved("photo"),
                try saved("scan"),
            ]
        }
    }
#endif
