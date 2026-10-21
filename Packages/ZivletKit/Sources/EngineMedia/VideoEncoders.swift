import ZivletCore
import ZivletEngineKit

/// The `-c:v …` part of a video argv and the lane it runs on (03b §5.5).
struct VideoEncoding: Sendable, Equatable {
    let args: [String]
    let lane: Lane
    /// HEVC Main 10 keeps HDR, so no tone-mapping is added in front of it.
    let isHEVCMain10: Bool
}

/// Video copy rules and encoders per target (03b §5.3, §5.5).
enum VideoEncoders {
    static let hevcTag = ["-tag:v", "hvc1"]
    static let tenBit = 10

    /// `-c:v copy` (+ tag) when the target stores the source stream as is; `nil` means re-encode.
    static func copyArgs(_ r: MediaPlanRequest, _ video: StreamInfo) -> [String]? {
        guard isCopyable(r, video), !exceedsHeightLimit(r.options.heightLimit, video) else { return nil }
        return ["-c:v", "copy"] + (video.codec == "hevc" ? hevcTag : [])
    }

    /// Encoder for a re-encode into `target`. `alpha` keeps transparency (an alpha source, or GIF, into mov or webm).
    static func encode(_ r: MediaPlanRequest, _ video: StreamInfo, alpha: Bool) throws(MediaPlanError)
        -> VideoEncoding
    {
        let tier = r.options.tier
        switch r.target {
        case .mp4, .mov, .mkv:
            return appleFamily(r, video, alpha: alpha)
        case .webm:
            return VideoEncoding(args: vp9(tier, alpha: alpha), lane: .swVideo, isHEVCMain10: false)
        case .avi:
            let args = ["-c:v", "mpeg4", "-vtag", "xvid", "-fps_mode", "cfr", "-q:v", pick(tier, 5, 3, 2)]
            return VideoEncoding(args: args, lane: .swVideo, isHEVCMain10: false)
        case .wmv:
            let args = ["-c:v", "wmv2", "-fps_mode", "cfr", "-q:v", pick(tier, 5, 3, 2)]
            return VideoEncoding(args: args, lane: .swVideo, isHEVCMain10: false)
        default:
            throw .pairNotSupported(r.sourceFormat, r.target)
        }
    }

    /// Container flags written after the metadata maps.
    static func containerArgs(_ target: FormatID) -> [String] {
        target == .mp4 || target == .mov ? ["-movflags", "+faststart"] : []
    }

    private static func isCopyable(_ r: MediaPlanRequest, _ video: StreamInfo) -> Bool {
        let mpeg4Copyable = video.codec == "mpeg4" && video.hasBFrames == 0
        switch r.target {
        case .mp4:
            let av1Copyable =
                video.codec == "av1" && r.capabilities.av1HardwareDecode && !r.options.maximumCompatibility
            return ["h264", "hevc"].contains(video.codec) || av1Copyable || mpeg4Copyable
        case .mov:
            return ["h264", "hevc", "prores", "mjpeg"].contains(video.codec) || mpeg4Copyable
        case .webm: return ["vp8", "vp9", "av1"].contains(video.codec)
        case .avi: return ["mpeg4", "mjpeg"].contains(video.codec)  // H.264 is re-encoded (index D-M3-9)
        case .wmv: return ["wmv1", "wmv2"].contains(video.codec)
        default: return false
        }
    }

    /// mp4, mov, mkv: VideoToolbox when present (index D12 fallback to libx264).
    private static func appleFamily(_ r: MediaPlanRequest, _ video: StreamInfo, alpha: Bool) -> VideoEncoding {
        let tier = r.options.tier
        guard r.capabilities.videoToolbox else {
            let args = ["-c:v", "libx264", "-preset", "medium", "-crf", pick(tier, 26, 23, 20), "-pix_fmt", "yuv420p"]
            return VideoEncoding(args: args, lane: .swVideo, isHEVCMain10: false)
        }
        let quality = ["-q:v", pick(tier, 48, 60, 72)]
        if alpha && r.target == .mov {
            let args = ["-c:v", "hevc_videotoolbox", "-pix_fmt", "bgra", "-alpha_quality", "0.75"] + hevcTag + quality
            return VideoEncoding(args: args, lane: .hwVideo, isHEVCMain10: false)
        }
        if r.target != .mkv && (video.bitDepth >= tenBit || video.isHDR) {
            let args = ["-c:v", "hevc_videotoolbox", "-profile:v", "main10", "-pix_fmt", "p010le"] + hevcTag + quality
            return VideoEncoding(args: args, lane: .hwVideo, isHEVCMain10: true)
        }
        let tag = r.target == .mkv ? [] : ["-tag:v", "avc1"]
        let args =
            ["-c:v", "h264_videotoolbox", "-profile:v", "high", "-allow_sw", "1", "-pix_fmt", "yuv420p"] + tag + quality
        return VideoEncoding(args: args, lane: .hwVideo, isHEVCMain10: false)
    }

    private static func vp9(_ tier: QualityTier, alpha: Bool) -> [String] {
        ["-c:v", "libvpx-vp9", "-b:v", "0", "-row-mt", "1", "-tile-columns", "2", "-deadline", "good"]
            + ["-cpu-used", "5", "-pix_fmt", alpha ? "yuva420p" : "yuv420p", "-crf", pick(tier, 37, 32, 27)]
    }

    private static func pick(_ tier: QualityTier, _ small: Int, _ standard: Int, _ best: Int) -> String {
        String(AudioEncoders.pick(tier, small, standard, best))
    }

    /// Re-encode filters (03b §5.2 order): tone-map, then the height cap or even dimensions.
    static func filters(_ r: MediaPlanRequest, _ video: StreamInfo, _ encoding: VideoEncoding) -> [String] {
        let toneMap = video.isHDR && !encoding.isHEVCMain10 ? [FFmpegArgs.toneMapToSDR(HDRSignal(video))] : []
        let chain = toneMap + scale(r.options.heightLimit, video)
        return chain.isEmpty ? [] : ["-vf", chain.joined(separator: ",")]
    }

    private static func scale(_ heightLimit: Int?, _ video: StreamInfo) -> [String] {
        if let heightLimit, exceedsHeightLimit(heightLimit, video) { return ["scale=-2:\(heightLimit)"] }
        return hasOddDimension(video) ? [FFmpegArgs.evenDimensions] : []
    }

    /// A copy cannot honour a height cap, so a taller source is re-encoded and scaled.
    private static func exceedsHeightLimit(_ heightLimit: Int?, _ video: StreamInfo) -> Bool {
        guard let heightLimit, let height = video.height else { return false }
        return height > heightLimit
    }

    static func hasOddDimension(_ video: StreamInfo) -> Bool {
        [video.width, video.height].contains { ($0 ?? 0) % 2 != 0 }
    }
}
