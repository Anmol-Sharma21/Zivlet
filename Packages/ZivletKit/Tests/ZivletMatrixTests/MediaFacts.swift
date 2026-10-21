import Foundation
import ZivletEngineKit

/// What ffprobe says about one stream, for the property checks.
struct StreamFacts: Sendable, Equatable {
    let kind: String
    let codec: String
    let width: Int?
    let height: Int?
    let channels: Int?
    let sampleRate: Int?
    let rotation: Int
    let alphaMode: Bool
    let isAttachedPicture: Bool

    /// Width and height as shown: a ±90° display matrix swaps them.
    var displaySize: (width: Int, height: Int)? {
        guard let width, let height else { return nil }
        return abs(rotation) % 180 == 90 ? (height, width) : (width, height)
    }
}

/// What ffprobe says about a media file. Immutable; built by `MediaFacts.read`.
struct MediaFacts: Sendable, Equatable {
    let duration: Double?
    let streams: [StreamFacts]

    var video: StreamFacts? { streams.first { $0.kind == "video" && !$0.isAttachedPicture } }
    var audio: [StreamFacts] { streams.filter { $0.kind == "audio" } }

    static let entries =
        "format=duration:stream=codec_type,codec_name,width,height,channels,sample_rate"
        + ":stream_tags=alpha_mode:stream_side_data=rotation:stream_disposition=attached_pic"

    static func read(_ url: URL, ffprobe: URL) async throws -> MediaFacts {
        let request = SubprocessRequest(
            executable: ffprobe, arguments: ["-v", "error", "-show_entries", entries, "-of", "json", url.path])
        let result = try await SubprocessRunner().run(request)
        guard result.termination == .exited(0) else {
            throw MatrixFailure("ffprobe cannot open \(url.lastPathComponent): \(result.stderrTail)")
        }
        return try parse(result.stdout)
    }

    static func parse(_ json: Data) throws -> MediaFacts {
        let probe = try JSONDecoder().decode(Probe.self, from: json)
        return MediaFacts(duration: probe.format?.duration.flatMap(Double.init), streams: probe.streams.map(\.facts))
    }

    private struct Probe: Decodable {
        let format: Format?
        let streams: [Stream]
    }

    private struct Format: Decodable {
        let duration: String?
    }

    private struct Stream: Decodable {
        let codecType: String
        let codecName: String?
        let width: Int?
        let height: Int?
        let channels: Int?
        let sampleRate: String?
        let tags: [String: String]?
        let sideDataList: [SideData]?
        let disposition: [String: Int]?

        enum CodingKeys: String, CodingKey {
            case codecType = "codec_type", codecName = "codec_name", width, height, channels
            case sampleRate = "sample_rate", tags, sideDataList = "side_data_list", disposition
        }

        var facts: StreamFacts {
            let alpha = tags?.first { $0.key.lowercased() == "alpha_mode" }?.value == "1"
            return StreamFacts(
                kind: codecType, codec: codecName ?? "?", width: width, height: height, channels: channels,
                sampleRate: sampleRate.flatMap { Int($0) }, rotation: sideDataList?.compactMap(\.rotation).first ?? 0,
                alphaMode: alpha, isAttachedPicture: disposition?["attached_pic"] == 1)
        }
    }

    private struct SideData: Decodable {
        let rotation: Int?
    }
}

/// A matrix step that could not run or whose result is wrong, with the reason in Zivlet's words.
struct MatrixFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
