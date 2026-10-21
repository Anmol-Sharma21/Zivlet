import ZivletCore
import ZivletEngineKit

/// GIF output with a two-branch palette graph, and GIF input flattened or kept with alpha (03b §5.6).
enum GIFPlanner {
    static let maxLegacyFrameRate = 50
    static let paletteTail =
        "split[a][b];[a]palettegen=stats_mode=diff:max_colors=256[p];[b][p]paletteuse=dither="

    static func videoToGIF(_ r: MediaPlanRequest) throws(MediaPlanError) -> FFmpegPlan {
        guard let video = r.info.primaryVideo else { throw .noVideoTrack }
        let toneMap = video.isHDR ? FFmpegArgs.toneMapToSDR(HDRSignal(video)) + "," : ""
        let scale = r.options.gifWidthLimit.map { "scale='min(\($0),iw)':-2:flags=lanczos," } ?? ""
        let graph =
            "[0:\(video.index)]" + toneMap + "fps=\(frameRate(r.options.gifFPS, video))," + scale
            + paletteTail + r.options.gifDither.rawValue + ":diff_mode=rectangle"
        let argv =
            r.prefix + ["-filter_complex", graph, "-an", "-loop", "0"]
            + FFmpegArgs.output(muxer: FFmpegArgs.muxer(for: r.target), staged: r.staged)
        return FFmpegPlan(
            single: argv, expectedDurationMicros: r.info.durationMicros, lane: .swVideo)
    }

    static func gifToVideo(_ r: MediaPlanRequest) throws(MediaPlanError) -> FFmpegPlan {
        guard let video = r.info.primaryVideo else { throw .noVideoTrack }
        let keepsAlpha = r.target == .webm || (r.target == .mov && r.capabilities.videoToolbox)
        let encoding = try VideoEncoders.encode(r, video, alpha: keepsAlpha)
        let input = keepsAlpha ? ["-map", "0:\(video.index)"] : try flatten(video)
        let argv =
            r.prefix + input + encoding.args + rate(r.target, video)
            + FFmpegArgs.metadata(preserve: r.options.keepMetadata)
            + VideoEncoders.containerArgs(r.target)
            + FFmpegArgs.output(muxer: FFmpegArgs.muxer(for: r.target), staged: r.staged)
        return FFmpegPlan(
            single: argv, expectedDurationMicros: r.info.durationMicros, lane: encoding.lane)
    }

    /// F = min(option, ⌊source fps⌋), at least 1; the option alone when the probe has no usable rate.
    static func frameRate(_ option: Int, _ video: StreamInfo) -> Int {
        guard let fps = video.usableFrameRate else { return option }
        return max(1, min(option, Int(fps.rounded(.down))))
    }

    /// Composites the frames over white. The canvas needs the probed size; without it the stream is unusable.
    private static func flatten(_ video: StreamInfo) throws(MediaPlanError) -> [String] {
        guard let width = video.width, let height = video.height else { throw .noVideoTrack }
        let even = VideoEncoders.hasOddDimension(video) ? FFmpegArgs.evenDimensions + "," : ""
        let graph =
            "color=white:s=\(width)x\(height)[bg];[bg][0:\(video.index)]overlay=shortest=1," + even
            + "format=yuv420p[v]"
        return ["-filter_complex", graph, "-map", "[v]"]
    }

    /// Variable rate where the container allows it; avi/wmv get a constant rate capped at 50.
    private static func rate(_ target: FormatID, _ video: StreamInfo) -> [String] {
        guard target == .avi || target == .wmv else { return ["-fps_mode", "vfr"] }
        guard let fps = video.usableFrameRate else { return [] }
        return ["-r", String(min(Int(fps.rounded()), maxLegacyFrameRate))]
    }
}
