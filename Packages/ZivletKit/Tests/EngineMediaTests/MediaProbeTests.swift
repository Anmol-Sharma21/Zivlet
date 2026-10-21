import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import EngineMedia

/// ffprobe JSON shaped like real output (03b §5.1): numbers as numbers, rates and sizes as strings.
enum ProbeJSON {
    static func stream(_ index: Int, _ type: String, _ codec: String, _ extra: String = "", picture: Int = 0) -> String
    {
        #"{"index":\#(index),"codec_type":"\#(type)","codec_name":"\#(codec)"\#(extra),"#
            + #""disposition":{"default":\#(index == 0 ? 1 : 0),"attached_pic":\#(picture)}}"#
    }

    static func file(_ format: String, duration: String = "\"10.5\"", _ streams: String...) -> String {
        #"{"streams":[\#(streams.joined(separator: ","))],"format":{"format_name":"\#(format)","duration":\#(duration)}}"#
    }

    static let h264 = stream(
        0, "video", "h264",
        #","width":1920,"height":1080,"pix_fmt":"yuv420p","has_b_frames":2,"avg_frame_rate":"30000/1001","#
            + #""bits_per_raw_sample":"8","color_transfer":"bt709""#)
    static let aac = stream(1, "audio", "aac", #","sample_rate":"48000","channels":2,"sample_fmt":"fltp""#)
    static let mp4 = file("mov,mp4,m4a,3gp,3g2,mj2", h264, aac)
    static let hdr = file(
        "mov,mp4,m4a,3gp,3g2,mj2",
        stream(0, "video", "hevc", #","width":3840,"height":2160,"pix_fmt":"yuv420p10le","color_transfer":"smpte2084""#)
    )
    static let coverArt = file(
        "mp3", stream(0, "audio", "mp3", #","sample_rate":"44100","channels":1"#),
        stream(1, "video", "mjpeg", #","width":32,"height":32,"pix_fmt":"yuvj444p""#, picture: 1))
    static let mkvSubs = file(
        "matroska,webm", stream(0, "video", "vp9", #","width":640,"height":360"#),
        stream(1, "audio", "opus", #","sample_rate":"48000","channels":6"#), stream(2, "subtitle", "subrip"),
        stream(3, "attachment", "ttf"))
}

@Suite("ffprobe JSON → MediaInfo (P1-02, P1-03; untrusted input)")
struct MediaProbeTests {
    func parse(_ json: String) throws -> MediaInfo { try MediaProbe.parse(Data(json.utf8)) }

    @Test func parsesAVideoWithAudio() throws {
        let info = try parse(ProbeJSON.mp4)
        #expect(info.formatName == "mov,mp4,m4a,3gp,3g2,mj2")
        #expect(info.durationMicros == 10_500_000)
        let video = try #require(info.primaryVideo)
        #expect(video.codec == "h264" && video.width == 1920 && video.height == 1080 && video.hasBFrames == 2)
        #expect(abs((video.avgFrameRate ?? 0) - 29.97) < 0.01)
        #expect(video.bitsPerRawSample == 8 && video.isDefault && !video.isHDR)
        let audio = try #require(info.primaryAudio)
        #expect(audio.sampleRate == 48_000 && audio.channels == 2 && audio.sampleFmt == "fltp")
    }

    @Test func recognisesHDRTenBitVideo() throws {
        let video = try #require(try parse(ProbeJSON.hdr).primaryVideo)
        #expect(video.isHDR && video.bitDepth == 10)
    }

    @Test func coverArtIsAnAttachedPictureNotThePrimaryVideo() throws {
        let info = try parse(ProbeJSON.coverArt)
        #expect(info.primaryVideo == nil)
        #expect(info.cover?.index == 1)
    }

    @Test func keepsSubtitleAndAttachmentKinds() throws {
        #expect(try parse(ProbeJSON.mkvSubs).streams.map(\.kind) == [.video, .audio, .subtitle, .attachment])
    }

    @Test func unknownKindsBecomeDataAndMissingCodecsAreUnknown() throws {
        let info = try parse(#"{"streams":[{"index":0,"codec_type":"weird"}],"format":{}}"#)
        #expect(info.streams.map(\.kind) == [.data])
        #expect(info.streams.first?.codec == "unknown")
        #expect(info.formatName == "" && info.durationMicros == nil)
    }

    @Test(arguments: [
        #""N/A""#, #""-3""#, #""nan""#, #""1e300""#, "true", #""""#,
    ])
    func implausibleDurationsAreUnknown(duration: String) throws {
        #expect(try parse(ProbeJSON.file("mp3", duration: duration)).durationMicros == nil)
    }

    @Test func numbersArriveAsNumbersOrStrings() throws {
        let json = ProbeJSON.file(
            "wav", duration: "2",
            ProbeJSON.stream(0, "audio", "pcm_s24le", #","sample_rate":44100,"channels":"2","bits_per_raw_sample":24"#))
        let audio = try #require(try parse(json).primaryAudio)
        #expect(audio.sampleRate == 44_100 && audio.channels == 2 && audio.bitsPerRawSample == 24)
    }

    @Test(arguments: [
        #","width":0,"height":-5"#, #","width":99999999,"height":1080"#, #","width":"wide","height":[1]"#,
    ])
    func implausibleDimensionsAreDropped(extra: String) throws {
        let video = try #require(
            try parse(ProbeJSON.file("matroska,webm", ProbeJSON.stream(0, "video", "vp9", extra))).primaryVideo)
        #expect(video.width == nil || video.height == nil)
    }

    @Test(arguments: ["", "{", "[]", "null", #"{"streams":"x"}"#, #"{"streams":[1,2]}"#])
    func malformedJSONIsATypedError(json: String) {
        #expect(throws: MediaProbeError.malformed) { try parse(json) }
    }

    @Test func oversizedOutputIsRefusedBeforeParsing() {
        let huge = Data(repeating: UInt8(ascii: " "), count: MediaProbe.maxOutputBytes + 1)
        #expect(throws: MediaProbeError.tooLarge) { try MediaProbe.parse(huge) }
    }

    @Test func tooManyStreamsAreRefused() {
        let streams = (0...MediaProbe.maxStreams).map { ProbeJSON.stream($0, "data", "bin") }.joined(separator: ",")
        #expect(throws: MediaProbeError.tooLarge) { try parse(#"{"streams":[\#(streams)],"format":{}}"#) }
    }

    @Test func deepNestingFailsCleanly() {
        let deep = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        #expect(throws: MediaProbeError.malformed) { try parse(#"{"streams":\#(deep)}"#) }
    }

    /// Fuzz-style: every prefix and 3,000 seeded byte mutations of a real-shaped document either parse to values
    /// inside the plausibility bounds or throw a typed error. A crash fails the whole run.
    @Test func truncatedAndMutatedDocumentsNeverCrash() {
        let seed = Array(ProbeJSON.mkvSubs.utf8)
        var rng = SplitMix64(seed: 0x5A75_0A)
        let prefixes = (0..<seed.count).map { Array(seed.prefix($0)) }
        let mutants = (0..<3_000).map { _ -> [UInt8] in
            var bytes = seed
            for _ in 0..<Int.random(in: 1...4, using: &rng) {
                bytes[Int.random(in: 0..<bytes.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng)
            }
            return bytes
        }
        for bytes in prefixes + mutants {
            guard let info = try? MediaProbe.parse(Data(bytes)) else { continue }
            #expect(info.streams.allSatisfy { ($0.width ?? 1) > 0 && ($0.channels ?? 1) > 0 && $0.index >= 0 })
        }
    }

    @Test func probeArgumentsWhitelistProtocolsAndDemuxers() {
        let args = MediaProbe.arguments(for: "/in/clip.mov")
        #expect(args.contains(subsequence: ["-protocol_whitelist", "file"]))
        #expect(
            args.contains(subsequence: ["-format_whitelist", "mov,matroska,webm,avi,asf,mp3,wav,flac,ogg,aiff,gif"]))
        #expect(args.last == "file:/in/clip.mov")
    }

    @Test(arguments: [
        (FormatID.mp4, "mov,mp4,m4a,3gp,3g2,mj2", true), (.webm, "matroska,webm", true), (.opus, "ogg", true),
        (.mp4, "hls", false), (.mkv, "concat", false), (.wav, "", false), (.mov, "movie", false),
    ])
    func theContainerMustMatchTheExtension(source: FormatID, formatName: String, confirmed: Bool) {
        #expect(MediaProbe.confirms(MediaInfo(formatName: formatName), source: source) == confirmed)
    }
}
