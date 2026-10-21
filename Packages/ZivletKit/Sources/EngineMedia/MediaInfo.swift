/// Kind of one probed stream (03b §5.1).
public enum StreamKind: String, Sendable, Codable {
    case video, audio, subtitle, attachment, data
}

/// One stream as reported by the probe (03b §5.1). Immutable; derived predicates are computed.
public struct StreamInfo: Sendable, Codable, Equatable {
    public let index: Int
    public let kind: StreamKind
    public let codec: String
    public let width: Int?
    public let height: Int?
    public let pixFmt: String?
    public let bitsPerRawSample: Int?
    public let hasBFrames: Int?
    public let colorTransfer: String?
    /// ffprobe `color_primaries` and `color_space` (the matrix), as ffprobe names them.
    public let colorPrimaries: String?
    public let colorSpace: String?
    public let avgFrameRate: Double?
    public let sampleRate: Int?
    public let channels: Int?
    public let sampleFmt: String?
    public let isAttachedPic: Bool
    public let isDefault: Bool

    public init(
        index: Int, kind: StreamKind, codec: String, width: Int? = nil, height: Int? = nil, pixFmt: String? = nil,
        bitsPerRawSample: Int? = nil, hasBFrames: Int? = nil, colorTransfer: String? = nil,
        colorPrimaries: String? = nil, colorSpace: String? = nil, avgFrameRate: Double? = nil, sampleRate: Int? = nil,
        channels: Int? = nil, sampleFmt: String? = nil,
        isAttachedPic: Bool = false, isDefault: Bool = false
    ) {
        self.index = index
        self.kind = kind
        self.codec = codec
        self.width = width
        self.height = height
        self.pixFmt = pixFmt
        self.bitsPerRawSample = bitsPerRawSample
        self.hasBFrames = hasBFrames
        self.colorTransfer = colorTransfer
        self.colorPrimaries = colorPrimaries
        self.colorSpace = colorSpace
        self.avgFrameRate = avgFrameRate
        self.sampleRate = sampleRate
        self.channels = channels
        self.sampleFmt = sampleFmt
        self.isAttachedPic = isAttachedPic
        self.isDefault = isDefault
    }

    static let hdrTransfers: Set<String> = ["smpte2084", "arib-std-b67"]
    static let alphaPixelFormats: Set<String> = [
        "yuva420p", "yuva444p", "rgba", "bgra", "argb", "abgr", "gbrap", "ya8",
    ]
    /// Above this the probe value is treated as garbage (a hostile or broken file).
    static let maxPlausibleFrameRate = 1_000.0

    /// `avgFrameRate` when it is finite and in (0, 1000]; nil otherwise, so planners never convert NaN, ±∞ or huge
    /// probe values to `Int`.
    public var usableFrameRate: Double? {
        guard let fps = avgFrameRate, fps.isFinite, fps > 0, fps <= Self.maxPlausibleFrameRate else { return nil }
        return fps
    }

    /// PQ or HLG transfer.
    public var isHDR: Bool { colorTransfer.map(Self.hdrTransfers.contains) ?? false }

    public var hasAlpha: Bool { pixFmt.map(Self.alphaPixelFormats.contains) ?? false }

    /// A genuinely float PCM source (`pcm_f32le`, `pcm_f64be`, …). Not derived from `sampleFmt`: every lossy decoder
    /// (mp3, aac, vorbis, opus, wma) reports `fltp`, and those sources follow the unknown-depth → 16-bit rule.
    public var isFloatAudio: Bool { codec.hasPrefix("pcm_f") }

    /// Bits per sample or component: the probe value when positive, else inferred from the pixel format.
    public var bitDepth: Int {
        if let bits = bitsPerRawSample, bits > 0 { return bits }
        guard let pixFmt else { return 8 }
        if pixFmt.hasSuffix("p10le") || pixFmt.hasSuffix("p010le") { return 10 }
        if pixFmt.hasSuffix("p12le") { return 12 }
        return 8
    }
}

/// A probed file (03b §5.1): container name, duration and streams in index order.
public struct MediaInfo: Sendable, Codable, Equatable {
    public let formatName: String
    public let durationMicros: Int64?
    public let streams: [StreamInfo]

    public init(formatName: String, durationMicros: Int64? = nil, streams: [StreamInfo] = []) {
        self.formatName = formatName
        self.durationMicros = durationMicros
        self.streams = streams
    }

    static let textSubtitleCodecs: Set<String> = ["subrip", "ass", "ssa", "webvtt", "mov_text", "text"]

    /// First video stream that is not an attached picture.
    public var primaryVideo: StreamInfo? { streams.first { $0.kind == .video && !$0.isAttachedPic } }

    /// Default-disposition audio, else the first audio stream.
    public var primaryAudio: StreamInfo? { audioStreams.first(where: \.isDefault) ?? audioStreams.first }

    public var audioStreams: [StreamInfo] { streams.filter { $0.kind == .audio } }

    /// Attached picture (cover art), mapped by index.
    public var cover: StreamInfo? { streams.first(where: \.isAttachedPic) }

    public var textSubtitles: [StreamInfo] {
        streams.filter { $0.kind == .subtitle && Self.textSubtitleCodecs.contains($0.codec) }
    }
}
