import Testing

@testable import ZivletEngineKit

@Test func elevenLanesWithStableRawValues() {
    #expect(Lane.allCases.count == 11)
    #expect(Lane.hwVideo.rawValue == "hwVideo")
}
