import ZivletCore
import ZivletEngineKit

/// Video to mkv is a stream copy (03b §5.3), but Matroska refuses data streams (QuickTime `tmcd` timecode, `mebx`
/// metadata) and the `mov_text` subtitle codec, so each stream is mapped by index instead of `-map 0`.
enum MatroskaRemux {
    /// Subtitle codecs Matroska stores as they are.
    static let copiedSubtitles: Set<String> = [
        "subrip", "ass", "ssa", "webvtt", "dvd_subtitle", "hdmv_pgs_subtitle", "dvb_subtitle",
    ]
    /// Timed text Matroska cannot store directly; converted to SubRip.
    static let subRipSubtitles: Set<String> = ["mov_text", "text"]

    static func plan(_ r: MediaPlanRequest) -> FFmpegPlan {
        let kept = r.info.streams.filter(keeps)
        let subtitles = kept.filter { $0.kind == .subtitle }
        let conversions = subtitles.enumerated().flatMap { offset, stream in
            subRipSubtitles.contains(stream.codec) ? ["-c:s:\(offset)", "srt"] : []
        }
        let argv =
            r.prefix + kept.flatMap { ["-map", "0:\($0.index)"] } + ["-c", "copy"] + conversions
            + FFmpegArgs.metadata(preserve: r.options.keepMetadata)
            + FFmpegArgs.output(muxer: FFmpegArgs.muxer(for: r.target), staged: r.staged)
        return FFmpegPlan(single: argv, expectedDurationMicros: r.info.durationMicros, lane: .remux)
    }

    /// Video (cover art included), audio and attachments always; subtitles Matroska stores or SubRip can carry.
    static func keeps(_ stream: StreamInfo) -> Bool {
        switch stream.kind {
        case .video, .audio, .attachment: true
        case .subtitle: copiedSubtitles.contains(stream.codec) || subRipSubtitles.contains(stream.codec)
        case .data: false
        }
    }
}
