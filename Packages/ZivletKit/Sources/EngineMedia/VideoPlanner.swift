import ZivletCore
import ZivletEngineKit

/// Video targets from a video source (03b §5.5). Argv order: maps, video, filters, audio, subtitles,
/// metadata, container flags, output (03b §5.2).
enum VideoPlanner {
    static func plan(_ r: MediaPlanRequest) throws(MediaPlanError) -> FFmpegPlan {
        guard let video = r.info.primaryVideo else { throw .noVideoTrack }
        if r.target == .mkv { return MatroskaRemux.plan(r) }
        let videoPart = try videoArgs(r, video)
        let audioStreams = VideoAudioRules.streams(r)
        let audio = VideoAudioRules.args(r.target, audioStreams)
        let subtitleCodec = subtitleCodec(r.target)
        let subtitles = subtitleCodec == nil ? [] : r.info.textSubtitles
        let subtitleArgs = subtitles.isEmpty ? [] : subtitleCodec.map { ["-c:s", $0] } ?? []
        let mapped = [video] + audioStreams + subtitles
        let argv =
            r.prefix + mapped.flatMap { ["-map", "0:\($0.index)"] } + videoPart.args + audio.args + subtitleArgs
            + FFmpegArgs.metadata(preserve: r.options.keepMetadata)
            + VideoEncoders.containerArgs(r.target)
            + FFmpegArgs.output(muxer: FFmpegArgs.muxer(for: r.target), staged: r.staged)
        let lane = videoPart.lane ?? (audio.reencodes ? .audio : .remux)
        return FFmpegPlan(
            single: argv, expectedDurationMicros: r.info.durationMicros, lane: lane)
    }

    /// Copy args (lane `nil`) or encoder plus filters (the encoder's lane).
    private static func videoArgs(_ r: MediaPlanRequest, _ video: StreamInfo) throws(MediaPlanError)
        -> (args: [String], lane: Lane?)
    {
        if let copy = VideoEncoders.copyArgs(r, video) { return (copy, nil) }
        let encoding = try VideoEncoders.encode(r, video, alpha: video.hasAlpha)
        return (encoding.args + VideoEncoders.filters(r, video, encoding), encoding.lane)
    }

    /// Text subtitles are converted for mp4/mov (`mov_text`) and webm (`webvtt`); avi/wmv carry none.
    private static func subtitleCodec(_ target: FormatID) -> String? {
        switch target {
        case .mp4, .mov: "mov_text"
        case .webm: "webvtt"
        default: nil
        }
    }
}
