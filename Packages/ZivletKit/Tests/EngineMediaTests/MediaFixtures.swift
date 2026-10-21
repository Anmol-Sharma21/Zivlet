import Foundation
import ZivletCore

@testable import EngineMedia

/// Probe values shaped like ffprobe output. Built per test; never mutated after construction.
enum Fx {
    static func video(
        _ index: Int, _ codec: String, _ w: Int = 1920, _ h: Int = 1080, fps: Double = 30,
        pixFmt: String = "yuv420p", hdr: Bool = false, bFrames: Int = 0
    ) -> StreamInfo {
        StreamInfo(
            index: index, kind: .video, codec: codec, width: w, height: h, pixFmt: pixFmt, hasBFrames: bFrames,
            colorTransfer: hdr ? "smpte2084" : "bt709", avgFrameRate: fps)
    }

    static func audio(
        _ index: Int, _ codec: String, rate: Int = 48_000, channels: Int = 2, bits: Int? = nil,
        sampleFmt: String = "fltp", isDefault: Bool = true
    ) -> StreamInfo {
        StreamInfo(
            index: index, kind: .audio, codec: codec, bitsPerRawSample: bits, sampleRate: rate, channels: channels,
            sampleFmt: sampleFmt, isDefault: isDefault)
    }

    static func cover(_ index: Int) -> StreamInfo {
        StreamInfo(index: index, kind: .video, codec: "mjpeg", isAttachedPic: true)
    }

    static func data(_ index: Int, _ codec: String) -> StreamInfo {
        StreamInfo(index: index, kind: .data, codec: codec)
    }

    static func subtitle(_ index: Int, _ codec: String) -> StreamInfo {
        StreamInfo(index: index, kind: .subtitle, codec: codec)
    }

    static func info(_ streams: StreamInfo...) -> MediaInfo {
        MediaInfo(formatName: "test", durationMicros: 10_000_000, streams: streams)
    }

    static func request(
        _ from: FormatID, _ to: FormatID, _ info: MediaInfo,
        options: MediaOptions? = nil, caps: MediaCapabilities = MediaCapabilities()
    ) -> MediaPlanRequest {
        MediaPlanRequest(
            source: "/in/x.\(from.rawValue)", sourceFormat: from, info: info, target: to,
            staged: "/out/y.\(to.rawValue)", options: options, capabilities: caps)
    }
}

enum Golden {
    struct Missing: Error { let name: String }

    /// Golden = argv after the fixed prefix, one line, space-separated (test paths contain no spaces).
    static func tail(_ name: String) throws -> [String] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Goldens") else {
            throw Missing(name: name)
        }
        let line = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return line.split(separator: " ").map(String.init)
    }
}
