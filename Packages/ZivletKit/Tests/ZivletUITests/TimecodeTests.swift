import AppKit
import SwiftUI
import Testing

@testable import ZivletUI

@Suite("Editable timecodes (P2-30, plan 20b A3): ss, mm:ss, hh:mm:ss with optional .fff")
@MainActor
struct TimecodeTests {
    static let end = Duration.seconds(134)  // 2:14

    @Test(arguments: [
        ("5", Duration.seconds(5)),
        ("90", Duration.seconds(90)),
        ("1:30", Duration.seconds(90)),
        ("01:30", Duration.seconds(90)),
        ("0:01:30.5", Duration.milliseconds(90_500)),
        ("1:02:03.25", Duration.milliseconds(3_723_250)),
        ("0:00.125", Duration.milliseconds(125)),
        (" 2:14 ", Duration.seconds(134)),
    ])
    func timesParse(text: String, duration: Duration) {
        #expect(Timecode.parse(text) == .success(duration))
    }

    @Test(arguments: [
        "", "-5", "1:-30", "1:60", "1:75:00", "1:2:3:4", "abc", "1:30.", "1:30.1234", "1::30", ":30", "1:3o",
    ])
    func malformedTimesSayHowToWriteOne(text: String) {
        #expect(Timecode.parse(text) == .failure(.malformed))
        #expect(TimecodeError.malformed.message == "Use a time like 1:30 or 0:01:30.5")
    }

    @Test func aTimePastTheEndIsRefusedWithTheEnd() {
        #expect(Timecode.parse("2:14", limit: Self.end) == .success(Self.end))
        #expect(Timecode.parse("2:15", limit: Self.end) == .failure(.pastEnd(Self.end)))
        #expect(TimecodeError.pastEnd(Self.end).message == "That's after the end (2:14)")
        #expect(TimecodeError.pastEnd(.seconds(3_723)).message == "That's after the end (1:02:03)")
    }

    @Test(arguments: [
        (Duration.milliseconds(3_723_250), "01:02:03.250"),
        (Duration.zero, "00:00:00.000"),
        (Duration.milliseconds(90_500), "00:01:30.500"),
    ])
    func timesFormatBackAndRoundTrip(duration: Duration, text: String) {
        #expect(Timecode.format(duration) == text)
        #expect(Timecode.parse(Timecode.format(duration)) == .success(duration))
    }

    @Test func theFieldKeepsTheLastValidValueAndShowsTheError() {
        var state = TimecodeEntry(value: .seconds(30), limit: Self.end)
        state = state.edited("1:30")
        #expect(state.value == .seconds(90) && state.error == nil)
        state = state.edited("9:00")
        #expect(state.value == .seconds(90) && state.error == .pastEnd(Self.end))
        state = state.edited("x")
        #expect(state.value == .seconds(90) && state.error == .malformed)
        #expect(state.text == "x")
    }

    @Test func theFieldDraws() {
        let view = NSHostingView(
            rootView: TimecodeField(label: "Start", value: .constant(.seconds(5)), limit: Self.end))
        view.layoutSubtreeIfNeeded()
        #expect(view.fittingSize.height > 0)
    }
}
