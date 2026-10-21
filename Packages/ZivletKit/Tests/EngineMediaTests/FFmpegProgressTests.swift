import Testing

@testable import EngineMedia

@Suite("ffmpeg -progress parser (P1-07, 03a §4.5)")
struct FFmpegProgressTests {
    /// Two blocks as ffmpeg 8.1 prints them with `-progress pipe:1 -nostats` (speed has a leading space).
    static let transcript = """
        frame=12
        fps=0.00
        bitrate=N/A
        total_size=48
        out_time_us=N/A
        out_time=N/A
        speed=N/A
        progress=continue
        frame=60
        total_size=16527
        out_time_us=2500000
        out_time_ms=2500000
        out_time=00:00:02.500000
        speed= 1.5x
        progress=continue
        bitrate=  66.1kbits/s
        out_time_us=-23220
        speed= 173x
        progress=end
        """

    static func events(_ text: String = transcript) -> [FFmpegProgressEvent] {
        var parser = FFmpegProgressParser()
        var events: [FFmpegProgressEvent] = []
        for line in text.split(separator: "\n") {
            let step = parser.consuming(String(line))
            parser = step.next
            if let event = step.event { events.append(event) }
        }
        return events
    }

    @Test func oneEventPerBlock() {
        #expect(
            Self.events() == [
                FFmpegProgressEvent(outTimeMicros: nil, speed: nil, isEnd: false, totalSize: 48),
                FFmpegProgressEvent(outTimeMicros: 2_500_000, speed: 1.5, isEnd: false, totalSize: 16_527),
                FFmpegProgressEvent(outTimeMicros: 0, speed: 173, isEnd: true),
            ])
    }

    @Test(arguments: [
        (FFmpegProgressEvent(outTimeMicros: 2_500_000, speed: nil, isEnd: false), Int64(10_000_000), 0.25),
        (FFmpegProgressEvent(outTimeMicros: 30_000_000, speed: nil, isEnd: false), 10_000_000, 1.0),
        (FFmpegProgressEvent(outTimeMicros: 0, speed: nil, isEnd: true), 10_000_000, 1.0),
    ])
    func fractionIsOutTimeOverExpected(event: FFmpegProgressEvent, expected: Int64, fraction: Double) {
        #expect(FFmpegProgressParser.fraction(event, expectedMicros: expected) == fraction)
    }

    @Test func unknownDurationOrOutTimeIsIndeterminate() {
        let running = FFmpegProgressEvent(outTimeMicros: 1_000, speed: 1, isEnd: false)
        #expect(FFmpegProgressParser.fraction(running, expectedMicros: nil) == nil)
        #expect(FFmpegProgressParser.fraction(running, expectedMicros: 0) == nil)
        let unknown = FFmpegProgressEvent(outTimeMicros: nil, speed: nil, isEnd: false)
        #expect(FFmpegProgressParser.fraction(unknown, expectedMicros: 5) == nil)
    }

    @Test func etaIsTheRemainingOutputTimeOverSpeed() {
        let events = Self.events("total_size=900\nout_time_us=4000000\nspeed=2.0x\nprogress=continue")
        let event = events[0]
        #expect(event.totalSize == 900)
        #expect(FFmpegProgressParser.eta(event, expectedMicros: 10_000_000) == .seconds(3))
    }

    @Test func noETAWithoutASpeedADurationOrTwoSecondsOfOutput() {
        let unknownSpeed = FFmpegProgressEvent(outTimeMicros: 4_000_000, speed: nil, isEnd: false)
        #expect(FFmpegProgressParser.eta(unknownSpeed, expectedMicros: 10_000_000) == nil)
        let early = FFmpegProgressEvent(outTimeMicros: 1_500_000, speed: 2, isEnd: false)
        #expect(FFmpegProgressParser.eta(early, expectedMicros: 10_000_000) == nil)
        let stalled = FFmpegProgressEvent(outTimeMicros: 4_000_000, speed: 0.001, isEnd: false)
        #expect(FFmpegProgressParser.eta(stalled, expectedMicros: 10_000_000) == nil)
        let running = FFmpegProgressEvent(outTimeMicros: 4_000_000, speed: 1, isEnd: false)
        #expect(FFmpegProgressParser.eta(running, expectedMicros: nil) == nil)
        let done = FFmpegProgressEvent(outTimeMicros: 4_000_000, speed: 1, isEnd: true)
        #expect(FFmpegProgressParser.eta(done, expectedMicros: 10_000_000) == nil)
        let past = FFmpegProgressEvent(outTimeMicros: 12_000_000, speed: 1, isEnd: false)
        #expect(FFmpegProgressParser.eta(past, expectedMicros: 10_000_000) == .zero)
    }

    @Test func speedNAIsNoSpeed() {
        let events = Self.events("out_time_us=4000000\nspeed=N/A\nprogress=continue")
        #expect(events[0].speed == nil)
    }

    @Test func linesWithoutAnEqualsSignOrForeignKeysAreIgnored() {
        let noise = (0..<10_000).map { "junk_\($0)=1" }.joined(separator: "\n")
        let events = Self.events("garbage\n" + noise + "\nout_time_us=7\nprogress=continue")
        #expect(events == [FFmpegProgressEvent(outTimeMicros: 7, speed: nil, isEnd: false)])
    }
}
