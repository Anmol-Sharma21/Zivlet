import AVFoundation
import EngineImage
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

/// Properties every matrix output must have (P1-61): it decodes; sizes, colour, alpha and frames are kept where the
/// target can hold them; durations agree within max(0.25 s, 1 %) (D-M3-16); codecs, channels and rates follow the
/// target rules of 03b §5.4–§5.6 and 11 §10.1.
enum PropertyChecks {
    static let durationFloor = 0.25
    static let durationShare = 0.01
    static let gifWidthLimit = 480
    static let aspectTolerance = 0.03
    static let maxRate = 48_000
    static let opaqueTargets: Set<FormatID> = [.jpg, .bmp]
    static let animatedTargets: Set<FormatID> = [.png, .webp, .heic]
    static let profileTargets: Set<FormatID> = [.jpg, .png, .webp, .heic, .tiff, .avif]

    static func verify(_ output: MatrixOutput, pair: ConversionPair, source: FixtureFacts, tools: MediaTools)
        async throws
    {
        switch (source, FormatRegistry.standard.format(pair.target).category) {
        case (.image(let facts), .pdf): try pdf(output.url, pair: pair, source: facts)
        case (.image(let facts), _): try raster(output.url, pair: pair, source: facts)
        case (.media(let facts), _): try await media(output.url, pair: pair, source: facts, tools: tools)
        }
    }

    static func raster(_ url: URL, pair: ConversionPair, source: ImageFacts) throws {
        let out = try ImageFacts.read(url)
        #expect(out.width == source.width && out.height == source.height, "size \(out.width)×\(out.height)")
        if source.hasAlpha == true {
            let kept = !opaqueTargets.contains(pair.target)
            #expect(out.hasAlpha == kept, kept ? "alpha lost" : "alpha not flattened")
        }
        if source.isP3 && profileTargets.contains(pair.target) {
            #expect(out.isP3, "P3 not kept (\(out.colourName ?? "no profile"))")
        }
        let frames = animatedTargets.contains(pair.target) ? source.frames : 1
        #expect(out.frames == frames, "\(out.frames) frames, expected \(frames)")
    }

    /// Images → PDF: one page per frame for a multi-page TIFF (capped), one page for everything else.
    static func pdf(_ url: URL, pair: ConversionPair, source: ImageFacts) throws {
        let pages = try #require(ImageFacts.pdfPages(url), "Core Graphics cannot open the PDF")
        let expected = pair.source == .tiff ? min(source.frames, ImagePlanner.maxPDFPages) : 1
        #expect(pages == expected, "\(pages) pages, expected \(expected)")
    }

    static func media(_ url: URL, pair: ConversionPair, source: MediaFacts, tools: MediaTools) async throws {
        try await decodes(url, tools: tools)
        let out = try await MediaFacts.read(url, ffprobe: tools.ffprobe)
        durationAgrees(out, source)
        switch FormatRegistry.standard.format(pair.target).category {
        case .audio: audio(out, pair: pair, source: source)
        case .gif: gif(out, source: source)
        default: try await video(out, url: url, pair: pair, source: source)
        }
    }

    /// The whole file decodes without an error (ffmpeg's null muxer).
    static func decodes(_ url: URL, tools: MediaTools) async throws {
        let request = SubprocessRequest(
            executable: tools.ffmpeg, arguments: ["-v", "error", "-nostdin", "-i", url.path, "-f", "null", "-"])
        let result = try await SubprocessRunner().run(request)
        #expect(result.termination == .exited(0), "does not decode: \(result.stderrTail)")
    }

    static func durationAgrees(_ out: MediaFacts, _ source: MediaFacts) {
        guard let expected = source.duration else { return }
        guard let actual = out.duration else {
            Issue.record("no duration")
            return
        }
        let tolerance = max(durationFloor, expected * durationShare)
        #expect(abs(actual - expected) <= tolerance, "duration \(actual) s, source \(expected) s")
    }

    static func audio(_ out: MediaFacts, pair: ConversionPair, source: MediaFacts) {
        guard let stream = out.audio.first, let input = source.audio.first else {
            Issue.record("no audio stream")
            return
        }
        #expect(out.audio.count == 1, "\(out.audio.count) audio streams")
        #expect(out.video == nil, "an audio target carries video")
        #expect(AudioRules.codecs(pair.target).contains(stream.codec), "audio codec \(stream.codec)")
        let channels = AudioRules.channels(pair.target, source: input.channels ?? 0)
        #expect(stream.channels == channels, "\(stream.channels ?? 0) channels, expected \(channels)")
        let rate = AudioRules.sampleRate(pair.target, source: input.sampleRate ?? 0)
        #expect(stream.sampleRate == rate, "\(stream.sampleRate ?? 0) Hz, expected \(rate)")
    }

    static func gif(_ out: MediaFacts, source: MediaFacts) {
        guard let video = out.video, let size = video.displaySize, let input = source.video?.displaySize else {
            Issue.record("no picture")
            return
        }
        #expect(video.codec == "gif" && out.audio.isEmpty)
        #expect(size.width <= min(gifWidthLimit, input.width), "GIF width \(size.width)")
        let ratio = Double(size.width) / Double(size.height)
        let expected = Double(input.width) / Double(input.height)
        #expect(abs(ratio - expected) / expected <= aspectTolerance, "aspect \(ratio), source \(expected)")
    }

    static func video(_ out: MediaFacts, url: URL, pair: ConversionPair, source: MediaFacts) async throws {
        guard let video = out.video, let size = video.displaySize, let input = source.video?.displaySize else {
            Issue.record("no picture")
            return
        }
        // Odd sizes are cut to even ones (03b §5.2).
        #expect(input.width - size.width <= 1 && input.height - size.height <= 1, "size \(size.width)×\(size.height)")
        #expect(size.width <= input.width && size.height <= input.height)
        let rules = VideoRules(pair: pair, sourceVideo: source.video?.codec ?? "")
        #expect(rules.videoCodecs.contains(video.codec), "video codec \(video.codec)")
        for stream in out.audio { #expect(rules.audioCodecs.contains(stream.codec), "audio codec \(stream.codec)") }
        if !source.audio.isEmpty { #expect(!out.audio.isEmpty, "audio dropped") }
        if pair.source == .gif && pair.target == .webm { #expect(video.alphaMode, "GIF transparency lost in WebM") }
        if [.mp4, .mov].contains(pair.target) {
            #expect(try await AVURLAsset(url: url).load(.isPlayable), "AVFoundation cannot play it")
        }
    }
}
