import ZivletCore

/// Palette dithering for GIF output (03b §5.6). The raw value is the ffmpeg `paletteuse` name.
public enum GIFDither: String, CaseIterable, Sendable, Codable {
    case sierra = "sierra2_4a"
    case bayer
}

/// User-facing media options (03b §5.4–5.6). Validated at the planner boundary.
public struct MediaOptions: Sendable, Codable, Equatable {
    public let tier: QualityTier
    public let keepMetadata: Bool
    /// Output height cap; `nil` keeps the source size.
    public let heightLimit: Int?
    public let maximumCompatibility: Bool
    public let gifFPS: Int
    /// GIF width cap; `nil` keeps the source width ("Original").
    public let gifWidthLimit: Int?
    public let gifDither: GIFDither

    static let allowedHeightLimits: Set<Int> = [2160, 1080, 720]
    static let allowedGIFFrameRates: Set<Int> = [10, 15, 24]
    static let allowedGIFWidths: Set<Int> = [320, 480, 640, 800]

    public init(
        tier: QualityTier = .standard, keepMetadata: Bool = true, heightLimit: Int? = nil,
        maximumCompatibility: Bool = true, gifFPS: Int = 15, gifWidthLimit: Int? = 480,
        gifDither: GIFDither = .sierra
    ) {
        self.tier = tier
        self.keepMetadata = keepMetadata
        self.heightLimit = heightLimit
        self.maximumCompatibility = maximumCompatibility
        self.gifFPS = gifFPS
        self.gifWidthLimit = gifWidthLimit
        self.gifDither = gifDither
    }

    /// Defaults per target: `.best` for mov (03b §5.5), `.standard` for everything else.
    public static func defaults(for target: FormatID) -> MediaOptions {
        MediaOptions(tier: target == .mov ? .best : .standard)
    }

    func validate() throws(MediaPlanError) {
        if let heightLimit, !Self.allowedHeightLimits.contains(heightLimit) {
            throw .invalidOption(.heightLimit, heightLimit)
        }
        if !Self.allowedGIFFrameRates.contains(gifFPS) {
            throw .invalidOption(.gifFPS, gifFPS)
        }
        if let gifWidthLimit, !Self.allowedGIFWidths.contains(gifWidthLimit) {
            throw .invalidOption(.gifWidthLimit, gifWidthLimit)
        }
    }
}

/// What the host machine offers to the planners (probed once by the runtime in P1).
public struct MediaCapabilities: Sendable, Codable, Equatable {
    public let videoToolbox: Bool
    public let av1HardwareDecode: Bool

    public init(videoToolbox: Bool = true, av1HardwareDecode: Bool = false) {
        self.videoToolbox = videoToolbox
        self.av1HardwareDecode = av1HardwareDecode
    }
}
