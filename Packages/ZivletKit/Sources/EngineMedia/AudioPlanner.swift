import ZivletCore
import ZivletEngineKit

/// Audio targets from any audio source or the primary audio of a video (03b §5.4).
enum AudioPlanner {
    static func plan(_ r: MediaPlanRequest) throws(MediaPlanError) -> FFmpegPlan {
        guard let audio = r.info.primaryAudio else { throw .noAudioTrack }
        let copy = AudioEncoders.copySet(r.target).contains(audio.codec)
        let cover = r.options.keepMetadata && AudioEncoders.coverTargets.contains(r.target) ? r.info.cover : nil
        let maps = ["-map", "0:\(audio.index)"] + (cover.map { ["-map", "0:\($0.index)"] } ?? [])
        let video = cover == nil ? ["-vn"] : ["-c:v", "copy", "-disposition:v:0", "attached_pic"]
        let audioArgs = copy ? ["-c:a", "copy"] : AudioEncoders.encode(r.target, audio, r.options.tier)
        let argv =
            r.prefix + maps + video + ["-sn", "-dn"] + audioArgs
            + FFmpegArgs.metadata(preserve: r.options.keepMetadata)
            + AudioEncoders.containerArgs(r.target)
            + FFmpegArgs.output(muxer: FFmpegArgs.muxer(for: r.target), staged: r.staged)
        return FFmpegPlan(
            single: argv, expectedDurationMicros: r.info.durationMicros,
            lane: copy ? .remux : .audio)
    }
}
