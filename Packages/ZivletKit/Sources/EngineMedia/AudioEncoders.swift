import ZivletCore

/// Audio target table (03b §5.4): copy sets, encoders per quality tier, container flags.
enum AudioEncoders {
    enum Endian: String { case little = "le", big = "be" }

    static let maxSampleRate = 48_000
    static let mp3MaxChannels = 2
    static let aacMaxChannels = 8
    static let opusStereoChannels = 2
    static let defaultPCMBits = 16

    /// Targets that carry the attached picture in M1; ogg/opus/aiff/wma drop it (index D11).
    static let coverTargets: Set<FormatID> = [.mp3, .m4a, .flac]

    /// small / standard / best selector, shared with the video planners.
    static func pick<Value>(_ tier: QualityTier, _ small: Value, _ standard: Value, _ best: Value) -> Value {
        switch tier {
        case .small: small
        case .standard: standard
        case .best: best
        }
    }

    /// Source codecs the target container stores without re-encoding.
    static func copySet(_ target: FormatID) -> Set<String> {
        switch target {
        case .mp3: ["mp3"]
        case .m4a: ["aac", "alac"]
        case .wav: ["pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_f32le"]
        case .aiff: ["pcm_s16be", "pcm_s24be", "pcm_s32be"]
        case .flac: ["flac"]
        case .ogg: ["vorbis"]
        case .opus: ["opus"]
        case .wma: ["wmav2"]
        default: []
        }
    }

    /// `-c:a …` and encoder flags. Only audio targets reach here (MediaPlanner routes by family).
    static func encode(_ target: FormatID, _ audio: StreamInfo, _ tier: QualityTier) -> [String] {
        switch target {
        case .mp3: mp3(audio, tier)
        case .m4a: aac(audio, tier)
        case .wav: ["-c:a", pcm(audio, endian: .little)]
        case .aiff: ["-c:a", pcm(audio, endian: .big)]
        case .flac: flac(audio, tier)
        case .ogg: ["-c:a", "libvorbis", "-q:a", pick(tier, "3", "6", "8")]
        case .opus: opus(audio, tier)
        case .wma: ["-c:a", "wmav2", "-b:a", pick(tier, "128k", "192k", "192k"), "-ac", "2"] + rateCap(audio)
        default: []
        }
    }

    /// PCM codec name: float keeps float in wav (`pcm_f32le`) and becomes 24-bit in aiff; else by bit depth.
    static func pcm(_ audio: StreamInfo, endian: Endian) -> String {
        if audio.isFloatAudio { return endian == .little ? "pcm_f32le" : "pcm_s24be" }
        let bits = knownBits(audio) ?? defaultPCMBits
        let depth = bits <= 16 ? "s16" : bits <= 24 ? "s24" : "s32"
        return "pcm_" + depth + endian.rawValue
    }

    /// Container flags written after the metadata maps.
    static func containerArgs(_ target: FormatID) -> [String] {
        switch target {
        case .mp3: ["-id3v2_version", "3", "-write_xing", "1"]
        case .m4a: ["-movflags", "+faststart"]
        case .wav: ["-rf64", "auto"]
        case .aiff: ["-write_id3v2", "1"]
        default: []
        }
    }

    private static func mp3(_ audio: StreamInfo, _ tier: QualityTier) -> [String] {
        ["-c:a", "libmp3lame", "-q:a", pick(tier, "4", "2", "0")] + rateCap(audio)
            + channelCap(audio, mp3MaxChannels)
    }

    private static func aac(_ audio: StreamInfo, _ tier: QualityTier) -> [String] {
        ["-c:a", "aac_at", "-b:a", pick(tier, "128k", "192k", "256k")] + rateCap(audio)
            + channelCap(audio, aacMaxChannels)
    }

    /// Deep or float sources → 24-bit; everything else → an explicit 16-bit sample format, because ffmpeg would
    /// otherwise pick s32 (24-bit) for the `fltp` output of a lossy decoder.
    private static func flac(_ audio: StreamInfo, _ tier: QualityTier) -> [String] {
        let isDeep = (knownBits(audio) ?? 0) > 16 || audio.isFloatAudio
        return ["-c:a", "flac", "-compression_level", pick(tier, "3", "8", "12")]
            + (isDeep ? ["-sample_fmt", "s32", "-bits_per_raw_sample", "24"] : ["-sample_fmt", "s16"])
    }

    private static func opus(_ audio: StreamInfo, _ tier: QualityTier) -> [String] {
        let surround = (audio.channels ?? 0) > opusStereoChannels
        return ["-c:a", "libopus", "-b:a", pick(tier, "96k", "128k", "192k")]
            + ["-vbr", "on", "-application", "audio", "-ar", "48000"]
            + (surround ? ["-mapping_family", "1"] : [])
    }

    /// `-ar 48000` above 48 kHz; shared with the wmv audio re-encode (wmav2 refuses higher rates).
    static func rateCap(_ audio: StreamInfo) -> [String] {
        (audio.sampleRate ?? 0) > maxSampleRate ? ["-ar", String(maxSampleRate)] : []
    }

    private static func channelCap(_ audio: StreamInfo, _ limit: Int) -> [String] {
        (audio.channels ?? 0) > limit ? ["-ac", String(limit)] : []
    }

    private static func knownBits(_ audio: StreamInfo) -> Int? {
        audio.bitsPerRawSample.flatMap { $0 > 0 ? $0 : nil }
    }
}
