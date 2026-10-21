import ZivletCore

/// Audio streams inside a video target (03b §5.3, §5.5): which are mapped, copied or re-encoded.
enum VideoAudioRules {
    static let legacyMaxChannels = 2
    static let wmvMaxSampleRate = AudioEncoders.maxSampleRate
    static let aacMaxChannels = 6

    /// mp4/mov carry every audio track; webm, avi and wmv carry the primary one.
    static func streams(_ r: MediaPlanRequest) -> [StreamInfo] {
        switch r.target {
        case .mp4, .mov: r.info.audioStreams
        default: r.info.primaryAudio.map { [$0] } ?? []
        }
    }

    /// Codec args for the mapped streams: `-c:a` for one stream, `-c:a:<i>` each for several.
    static func args(_ target: FormatID, _ streams: [StreamInfo]) -> (args: [String], reencodes: Bool) {
        let perStream = streams.map { copies(target, $0) ? ["-c:a", "copy"] : encode(target, $0) }
        let args = perStream.enumerated().flatMap { offset, codec in
            streams.count == 1 ? codec : ["-c:a:\(offset)"] + codec.dropFirst()
        }
        return (args, streams.contains { !copies(target, $0) })
    }

    static func copies(_ target: FormatID, _ audio: StreamInfo) -> Bool {
        let isStereoOrLess = (audio.channels ?? legacyMaxChannels) <= legacyMaxChannels
        switch target {
        case .mp4: return ["aac", "alac", "mp3", "ac3", "eac3"].contains(audio.codec)
        case .mov: return ["aac", "alac", "mp3"].contains(audio.codec) || audio.codec.hasPrefix("pcm_")
        case .webm: return ["opus", "vorbis"].contains(audio.codec)
        case .avi: return ["mp3", "pcm_s16le", "ac3"].contains(audio.codec) && isStereoOrLess
        case .wmv:
            let rateFits = (audio.sampleRate ?? wmvMaxSampleRate) <= wmvMaxSampleRate
            return audio.codec == "wmav2" && isStereoOrLess && rateFits
        default: return false
        }
    }

    /// Re-encode args, starting with `-c:a <encoder>`.
    static func encode(_ target: FormatID, _ audio: StreamInfo) -> [String] {
        switch target {
        case .webm: ["-c:a", "libopus", "-b:a", "128k", "-ar", "48000"]
        case .avi: ["-c:a", "libmp3lame", "-b:a", "192k", "-ac", "2"]
        case .wmv: ["-c:a", "wmav2", "-b:a", "192k", "-ac", "2"] + AudioEncoders.rateCap(audio)
        default:
            ["-c:a", "aac_at", "-b:a", "192k"]
                + ((audio.channels ?? 0) > aacMaxChannels ? ["-ac", String(aacMaxChannels)] : [])
        }
    }
}
