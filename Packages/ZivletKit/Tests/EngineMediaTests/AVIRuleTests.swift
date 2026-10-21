import Testing
import ZivletCore

@testable import EngineMedia

/// Found by the real-ffmpeg sweep: AVI cannot take H.264 from MP4/MOV/MKV as a stream copy (the AVCC bitstream needs
/// `h264_mp4toannexb`, and B-frame timestamps stretch the duration), so H.264 is re-encoded to MPEG-4 Part 2.
@Suite("AVI copy rule (index D-M3-9)")
struct AVIRuleTests {
    @Test(arguments: [FormatID.mp4, .mov, .mkv])
    func h264IsReencodedForAVI(source: FormatID) throws {
        let argv = try MediaPlanner.plan(Fx.request(source, .avi, Fx.info(Fx.video(0, "h264")))).passes[0].argv
        #expect(argv.contains(subsequence: ["-c:v", "mpeg4", "-vtag", "xvid"]))
    }

    @Test(arguments: ["mpeg4", "mjpeg"])
    func mpeg4AndMJPEGAreStillCopied(codec: String) throws {
        let argv = try MediaPlanner.plan(Fx.request(.mov, .avi, Fx.info(Fx.video(0, codec)))).passes[0].argv
        #expect(argv.contains(subsequence: ["-c:v", "copy"]))
    }
}
