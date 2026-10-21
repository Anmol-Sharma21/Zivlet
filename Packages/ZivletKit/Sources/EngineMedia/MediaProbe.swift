import Foundation
import ZivletCore

public enum MediaProbeError: Error, Equatable, Sendable {
    case malformed, tooLarge
}

/// ffprobe for user files (03b §5.1, 10 §8.9): only the `file` protocol and the advertised demuxers, JSON out.
/// The JSON describes an untrusted file, so every value is range-checked and an implausible one becomes `nil`.
public enum MediaProbe {
    public static let formatWhitelist = "mov,matroska,webm,avi,asf,mp3,wav,flac,ogg,aiff,gif"
    public static let maxOutputBytes = 4 << 20
    public static let maxStreams = 256

    static let maxDimension = 65_535
    static let maxSampleRate = 768_000
    static let maxChannels = 64
    static let maxBitDepth = 64
    static let maxDurationSeconds = 10_000_000.0

    public static func arguments(for path: String) -> [String] {
        [
            "-v", "error", "-hide_banner", "-of", "json", "-show_format", "-show_streams", "-protocol_whitelist",
            "file", "-format_whitelist", formatWhitelist, "file:" + path,
        ]
    }

    public static func parse(_ data: Data) throws(MediaProbeError) -> MediaInfo {
        guard data.count <= maxOutputBytes else { throw .tooLarge }
        let document: ProbeDocument
        do {
            document = try JSONDecoder().decode(ProbeDocument.self, from: data)
        } catch {
            throw .malformed
        }
        let streams = document.streams ?? []
        guard streams.count <= maxStreams else { throw .tooLarge }
        return MediaInfo(
            formatName: document.format?.formatName?.value ?? "",
            durationMicros: document.format?.duration?.number.flatMap(micros),
            streams: streams.enumerated().map { offset, stream in stream.info(fallbackIndex: offset) })
    }

    /// The probed container must be the demuxer the extension promises (03a §3.2): a playlist or concat script
    /// renamed `.mp4` reports another format and is refused before ffmpeg opens it.
    public static func confirms(_ info: MediaInfo, source: FormatID) -> Bool {
        info.formatName.split(separator: ",").contains { $0 == FFmpegArgs.demuxer(for: source) }
    }

    static func micros(_ seconds: Double) -> Int64? {
        guard seconds.isFinite, seconds >= 0, seconds <= maxDurationSeconds else { return nil }
        return Int64((seconds * 1_000_000).rounded())
    }

    static func bounded(_ value: Int?, _ range: ClosedRange<Int>) -> Int? {
        guard let value, range.contains(value) else { return nil }
        return value
    }
}

/// A JSON scalar that may arrive as a number, a string or something else; never fails to decode.
struct Scalar: Decodable {
    let value: String?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else {
            value = nil
        }
    }

    var number: Double? { value.flatMap(Double.init) }
    var integer: Int? { value.flatMap { Int($0) } }
}

struct ProbeDocument: Decodable {
    let streams: [ProbeStream]?
    let format: ProbeFormat?
}

struct ProbeFormat: Decodable {
    let formatName: Scalar?
    let duration: Scalar?

    enum CodingKeys: String, CodingKey { case formatName = "format_name", duration }
}

struct ProbeStream: Decodable {
    let index, codecType, codecName, width, height, pixFmt, bitsPerRawSample, hasBFrames: Scalar?
    let colorTransfer, avgFrameRate, sampleRate, channels, sampleFmt: Scalar?
    let disposition: [String: Scalar]?

    enum CodingKeys: String, CodingKey {
        case index, width, height, channels, disposition
        case codecType = "codec_type", codecName = "codec_name", pixFmt = "pix_fmt"
        case bitsPerRawSample = "bits_per_raw_sample", hasBFrames = "has_b_frames", colorTransfer = "color_transfer"
        case avgFrameRate = "avg_frame_rate", sampleRate = "sample_rate", sampleFmt = "sample_fmt"
    }

    func info(fallbackIndex: Int) -> StreamInfo {
        let probe = MediaProbe.self
        let width = probe.bounded(self.width?.integer, 1...probe.maxDimension)
        let height = probe.bounded(self.height?.integer, 1...probe.maxDimension)
        return StreamInfo(
            index: probe.bounded(index?.integer, 0...Int(Int32.max)) ?? fallbackIndex,
            kind: codecType?.value.flatMap(StreamKind.init(rawValue:)) ?? .data,
            codec: codecName?.value ?? "unknown", width: width, height: height, pixFmt: pixFmt?.value,
            bitsPerRawSample: probe.bounded(bitsPerRawSample?.integer, 1...probe.maxBitDepth),
            hasBFrames: probe.bounded(hasBFrames?.integer, 0...16), colorTransfer: colorTransfer?.value,
            avgFrameRate: avgFrameRate?.value.flatMap(Self.rate),
            sampleRate: probe.bounded(sampleRate?.integer, 1...probe.maxSampleRate),
            channels: probe.bounded(channels?.integer, 1...probe.maxChannels), sampleFmt: sampleFmt?.value,
            isAttachedPic: disposition?["attached_pic"]?.integer == 1, isDefault: disposition?["default"]?.integer == 1)
    }

    /// "30000/1001" → 29.97; a zero denominator or a non-number is `nil`.
    static func rate(_ text: String) -> Double? {
        let parts = text.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] != 0 else { return nil }
        let value = parts[0] / parts[1]
        return value.isFinite && value > 0 ? value : nil
    }
}
