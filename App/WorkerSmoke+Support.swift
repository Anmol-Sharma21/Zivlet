#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO
    import Synchronization
    import ZivletCore
    import ZivletEngineKit
    import ZivletRuntime
    import EngineImage

    /// One state change of one job of a smoke batch.
    struct SmokeEvent: Sendable {
        let index: Int
        let job: JobID
        let state: JobState
    }

    /// One batch on its own scheduler, whose image engine runs where the smoke's selection chose.
    struct SmokeBatch {
        let folder: URL
        let scheduler: JobScheduler

        init(folder: URL, selection: WorkerSelection) {
            self.folder = folder
            let engine = WorkerRoutedEngine(local: ImageEngine(), selection: selection)
            scheduler = JobScheduler(engines: [engine], records: nil)
        }

        /// Runs the batch and returns each job's last state, in input order; nil inputs fail the batch.
        func run(
            _ inputs: [(URL?, FormatID, FormatID)], onEvent: @escaping @MainActor (SmokeEvent) async -> Void
        ) async -> [JobState] {
            guard let requests = try? inputs.map(request) else { return [.failed(.unsupportedInput(.notAFile))] }
            let ids = requests.map(\.id)
            let events = scheduler.events
            let batch = await scheduler.submit(requests)
            var last: [JobID: JobState] = [:]
            for await event in events {
                if case .changed(_, let job, let state) = event, let index = ids.firstIndex(of: job) {
                    last[job] = state
                    await onEvent(SmokeEvent(index: index, job: job, state: state))
                }
                if event == .finished(batch) { break }
            }
            await scheduler.waitUntilIdle()
            return ids.map { last[$0] ?? .queued }
        }

        private func request(_ input: (URL?, FormatID, FormatID)) throws -> JobRequest {
            guard let url = input.0 else { throw JobError.unsupportedInput(.notAFile) }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let item = try InputItem(url: url, format: input.1, byteCount: size)
            return try JobRequest(input: item, operation: .convert(input.2), destination: folder)
        }
    }

    /// Named moments and once-only flags, shared by a step and its event handler.
    final class SmokeMarks: Sendable {
        private let state = Mutex<(stamps: [String: ContinuousClock.Instant], flags: Set<String>)>(([:], []))

        func stamp(_ name: String) {
            state.withLock { $0.stamps[name] = .now }
        }

        func has(_ name: String) -> Bool { state.withLock { $0.stamps[name] != nil || $0.flags.contains(name) } }

        /// True the first time only.
        func once(_ name: String) -> Bool { state.withLock { $0.flags.insert(name).inserted } }

        /// Milliseconds from one stamp to another; -1 when either is missing.
        func between(_ from: String, _ to: String) -> Int {
            state.withLock { state in
                guard let start = state.stamps[from], let end = state.stamps[to] else { return -1 }
                return SmokeClock.milliseconds(end - start)
            }
        }
    }

    struct SmokeClock {
        let start = ContinuousClock.now

        var ms: Int { Self.milliseconds(ContinuousClock.now - start) }

        static func milliseconds(_ duration: Duration) -> Int {
            Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
        }
    }

    /// Appends one JSON line per step.
    struct SmokeLog {
        struct Line: Codable {
            let step: String
            let ok: Bool
            let ms: Int
            let detail: String
        }

        let file: URL

        /// Job outcomes without paths: "saved", "cancelled" or the error's log name.
        static func describe(_ states: [JobState]) -> String {
            states.map { state in
                switch state {
                case .succeeded: "saved"
                case .cancelled: "cancelled"
                case .failed(let error): error.logDescription
                default: "unfinished"
                }
            }.joined(separator: ", ")
        }

        func write(_ step: String, ok: Bool, ms: Int, _ detail: String) {
            guard var data = try? JSONEncoder().encode(Line(step: step, ok: ok, ms: ms, detail: detail)) else { return }
            data.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: file) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: file)
            }
        }
    }

    /// The smoke's inputs, drawn into its folder: a small PNG and a 6000 × 4000 noise TIFF whose PNG encode takes
    /// seconds (long enough to cancel or kill during it).
    enum SmokeFixtures {
        static func png(in folder: URL) -> URL? {
            write(
                pixels(width: 64, height: 48, noise: false), width: 64, height: 48, type: "public.png",
                to: folder.appending(path: "photo.png"))
        }

        static func noiseTIFF(in folder: URL) -> URL? {
            write(
                pixels(width: 6000, height: 4000, noise: true), width: 6000, height: 4000, type: "public.tiff",
                to: folder.appending(path: "noise.tiff"))
        }

        private static func pixels(width: Int, height: Int, noise: Bool) -> [UInt8] {
            var bytes = [UInt8](repeating: 0x80, count: width * height * 4)
            guard noise else { return bytes }
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            for index in bytes.indices {
                seed ^= seed << 13
                seed ^= seed >> 7
                seed ^= seed << 17
                bytes[index] = UInt8(truncatingIfNeeded: seed)
            }
            return bytes
        }

        private static func write(_ bytes: [UInt8], width: Int, height: Int, type: String, to url: URL) -> URL? {
            var copy = bytes
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: &copy, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                let image = context.makeImage(),
                let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, image, nil)
            return CGImageDestinationFinalize(destination) ? url : nil
        }
    }
#endif
