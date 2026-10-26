#if DEBUG
    import Foundation
    import ZivletCore
    import ZivletTrigger

    /// Records file drags for the proximity and shake replays (P2-197, D-M5b-10). Debug builds only, and only when
    /// launched with `-ZivletRecordDragTraces normal|notch`: it keeps the live samples of one drag and, when the drag
    /// ends, writes one validated `DragTrace` (timings, positions, the button and the display's geometry; nothing
    /// about files) into its folder: 0700, each file 0600, `<yyyyMMdd-HHmmss>-<label>-<n>.json`. A drag over 20,000
    /// samples is not saved; at 2,000 files it stops and says so once. Log lines carry counts and labels only.
    public final class DragTraceRecorder {
        public static let sampleCap = 20_000
        public static let standardFileCap = 2_000
        /// `check-release-paths.sh` refuses this string in a Release binary.
        public static let launchFlag = "-ZivletRecordDragTraces"

        public let label: DragTrace.Label
        public private(set) var sampleCount = 0
        private let folder: URL
        private let display: (Point2D) -> TraceDisplay?
        private let os: String
        private let fileCap: Int
        private let now: () -> Date
        private let log: (String) -> Void
        private var samples: [DragTrace.Sample] = []
        private var first: Point2D?
        private var overCap = false
        private var saved = 0
        private var stopped = false

        public init(
            folder: URL, label: DragTrace.Label, display: @escaping (Point2D) -> TraceDisplay?,
            os: String = ProcessInfo.processInfo.operatingSystemVersionString, fileCap: Int = standardFileCap,
            now: @escaping () -> Date = Date.init, log: @escaping (String) -> Void
        ) {
            self.folder = folder
            self.label = label
            self.display = display
            self.os = os
            self.fileCap = fileCap
            self.now = now
            self.log = log
        }

        /// The value after the launch flag, if the flag is there.
        public static func launchValue(in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: launchFlag), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        /// The label the launch flag asks for; nil (do not record) for no flag or any other value.
        public static func label(fromLaunchValue value: String?) -> DragTrace.Label? {
            value.flatMap(DragTrace.Label.init(rawValue:))
        }

        /// `~/Library/Application Support/Zivlet/DragTraces`.
        public static func standardFolder() throws -> URL {
            try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
            ).appending(path: "Zivlet/DragTraces", directoryHint: .isDirectory)
        }

        /// One live sample of the current drag; past the cap it is dropped and the drag will not be saved.
        public func observe(_ sample: InputSample) {
            guard !stopped else { return }
            guard samples.count < Self.sampleCap else {
                overCap = true
                return
            }
            if first == nil { first = sample.location }
            let millis =
                Double(sample.uptime.components.seconds) * 1_000
                + Double(sample.uptime.components.attoseconds) / 1e15
            samples.append(
                DragTrace.Sample(
                    t: millis, x: sample.location.x, y: sample.location.y, down: sample.primaryButtonDown))
            sampleCount = samples.count
        }

        /// The drag ended: writes its trace and returns the file, or says in the log why it did not.
        @discardableResult
        public func dragEnded() -> URL? {
            defer { clear() }
            guard !stopped, !samples.isEmpty else { return nil }
            if overCap { return refuse("over \(Self.sampleCap) samples") }
            guard let first, let display = display(first) else { return refuse("no display under the drag") }
            do {
                let trace = try DragTrace(label: label, display: display, os: os, samples: samples)
                let file = try write(trace)
                log("DragTrace: saved \(trace.samples.count) samples")
                return file
            } catch let error as DragTraceError {
                return refuse(error.description)
            } catch RecorderError.folderFull {
                stopped = true
                log("DragTrace: folder full (\(fileCap) files), recording stopped")
                return nil
            } catch {
                return refuse("the file could not be written")
            }
        }

        // MARK: - Private

        private enum RecorderError: Error {
            case folderFull
        }

        private func refuse(_ reason: String) -> URL? {
            log("DragTrace: not saved (\(reason))")
            return nil
        }

        private func clear() {
            samples = []
            sampleCount = 0
            first = nil
            overCap = false
        }

        private func write(_ trace: DragTrace) throws -> URL {
            let manager = FileManager.default
            try manager.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            let existing = try manager.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }
            guard existing.count < fileCap else { throw RecorderError.folderFull }
            let data = try JSONEncoder().encode(trace)
            let file = nextFile(existing: Set(existing))
            let temporary = folder.appending(path: ".\(UUID().uuidString).tmp")
            guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600])
            else { throw CocoaError(.fileWriteUnknown) }
            do {
                try manager.moveItem(at: temporary, to: file)
            } catch {
                try? manager.removeItem(at: temporary)
                throw error
            }
            saved += 1
            return file
        }

        private func nextFile(existing: Set<String>) -> URL {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = formatter.string(from: now())
            var number = saved + 1
            while existing.contains("\(stamp)-\(label.rawValue)-\(number).json") { number += 1 }
            return folder.appending(path: "\(stamp)-\(label.rawValue)-\(number).json")
        }
    }
#endif
