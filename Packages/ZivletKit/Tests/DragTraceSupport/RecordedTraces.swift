import Foundation
import ZivletCore
import ZivletTrigger

/// Recorded drags for the owner's acceptance runs (OS-M5b-1), read from the folder named by `ZIVLET_DRAG_TRACES`.
/// Only the fields the shake test needs are read here: the label and the samples (`t` in milliseconds, `x`, `y`,
/// `down`), the shape the recorder writes. The full, validated trace model replaces this reader with task D3.
public struct RecordedTrace: Decodable, Sendable {
    public struct Sample: Decodable, Sendable {
        public let t: Double
        public let x: Double
        public let y: Double
        public let down: Bool
    }

    public let label: String
    public let samples: [Sample]

    /// The trace as live frame samples; samples with the button up are left out.
    public var inputSamples: [InputSample] {
        samples.filter(\.down).map {
            InputSample(
                uptime: .nanoseconds(Int64($0.t * 1e6)), source: .frame, primaryButtonDown: true, dragChangeCount: 1,
                dragHasFileTypes: true, location: Point2D(x: $0.x, y: $0.y))
        }
    }

    /// The folder named by `ZIVLET_DRAG_TRACES`, or nil when it is not set (CI and ordinary runs).
    public static var folder: URL? {
        ProcessInfo.processInfo.environment["ZIVLET_DRAG_TRACES"].map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Every `.json` trace directly in `folder`.
    public static func load(from folder: URL) throws -> [RecordedTrace] {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return try files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.map {
            try JSONDecoder().decode(RecordedTrace.self, from: Data(contentsOf: $0))
        }
    }
}
