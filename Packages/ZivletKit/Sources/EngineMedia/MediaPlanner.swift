import ZivletCore

/// Entry point: validates the request, then dispatches through the explicit route table (03b §5.2).
public enum MediaPlanner {
    /// `catalog` decides which pairs exist; `registry` gives each format's category for routing.
    public static func plan(
        _ request: MediaPlanRequest, catalog: ConversionCatalog = .standard, registry: FormatRegistry = .standard
    ) throws(MediaPlanError) -> FFmpegPlan {
        let request = try request.validated(catalog: catalog)
        switch try MediaRoute(request, registry: registry) {
        case .videoToGIF: return try GIFPlanner.videoToGIF(request)
        case .gifToVideo: return try GIFPlanner.gifToVideo(request)
        case .toAudio: return try AudioPlanner.plan(request)
        case .videoToVideo: return try VideoPlanner.plan(request)
        }
    }
}

/// Which planner handles a pair. Only audio, video and GIF categories route; anything else is not a media
/// conversion and is refused with `pairNotSupported` before a planner runs.
enum MediaRoute: Equatable {
    case videoToGIF, gifToVideo, toAudio, videoToVideo

    init(_ r: MediaPlanRequest, registry: FormatRegistry) throws(MediaPlanError) {
        switch (registry.format(r.sourceFormat).category, registry.format(r.target).category) {
        case (.video, .gif): self = .videoToGIF
        case (.gif, .video): self = .gifToVideo
        case (.audio, .audio), (.video, .audio): self = .toAudio
        case (.video, .video): self = .videoToVideo
        default: throw .pairNotSupported(r.sourceFormat, r.target)
        }
    }
}
