import ZivletCore

/// Audio target rules (03b §5.4, 11 §10.1): which codecs a target may hold, and the channels and rate it ends with.
enum AudioRules {
    static func codecs(_ target: FormatID) -> Set<String> {
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

    /// MP3 holds two channels at most, AAC eight; WMA is always stereo; the rest keep the source's count.
    static func channels(_ target: FormatID, source: Int) -> Int {
        switch target {
        case .mp3: min(source, 2)
        case .m4a: min(source, 8)
        case .wma: 2
        default: source
        }
    }

    /// Opus is always 48 kHz; MP3, AAC and WMA are capped at 48 kHz; lossless targets keep the source rate.
    static func sampleRate(_ target: FormatID, source: Int) -> Int {
        switch target {
        case .opus: PropertyChecks.maxRate
        case .mp3, .m4a, .wma: min(source, PropertyChecks.maxRate)
        default: source
        }
    }
}

/// Video target rules (03b §5.3, §5.5): WebM is VP9 + Opus, AVI MPEG-4 + MP3, WMV WMV2 + WMA; MP4 and MOV hold
/// H.264/HEVC (or a copied MPEG-4 Part 2) with AAC-family audio; MKV is a remux, so it keeps the source codec.
struct VideoRules {
    let videoCodecs: Set<String>
    let audioCodecs: Set<String>

    init(pair: ConversionPair, sourceVideo: String) {
        let apple: Set<String> = ["h264", "hevc", "mpeg4"]
        switch pair.target {
        case .webm: (videoCodecs, audioCodecs) = (["vp9"], ["opus"])
        case .avi: (videoCodecs, audioCodecs) = (["mpeg4"], ["mp3"])
        case .wmv: (videoCodecs, audioCodecs) = (["wmv2"], ["wmav2"])
        case .mp4: (videoCodecs, audioCodecs) = (apple, ["aac", "alac", "mp3", "ac3", "eac3"])
        case .mov: (videoCodecs, audioCodecs) = (apple, ["aac", "alac", "mp3", "pcm_s16le", "pcm_s24le", "pcm_f32le"])
        default:
            let remuxed: Set<String> = pair.source == .gif ? ["h264", "hevc"] : [sourceVideo]
            (videoCodecs, audioCodecs) = (remuxed, ["aac", "opus", "vorbis", "mp3", "pcm_s16le", "wmav2", "flac"])
        }
    }
}
