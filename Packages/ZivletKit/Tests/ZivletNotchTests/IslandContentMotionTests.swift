import NotchTestSupport
import Testing
import ZivletNotchCore

@testable import ZivletNotch

@Suite("Island content motion (19b D-NL13, §3.4)")
@MainActor
struct IslandContentMotionTests {
    @Test func contentEntersWithScaleAndFadeAndLeavesWithFade() {
        #expect(IslandAnimation.motion.contentTransition(reduceMotion: false) == .scaleAndFade(from: 0.96))
        #expect(IslandAnimation.motion.contentTransition(reduceMotion: true) == .fade)
    }

    @Test func theMotionKnowsWhenItIsReduced() {
        #expect(IslandMotion(reduceMotion: true).isReduced && !IslandMotion(reduceMotion: false).isReduced)
    }

    @Test func reduceMotionNeverScalesContent() throws {
        let host = makeHost(try OffscreenDisplays.notch())
        host.curves = IslandMotion(reduceMotion: true)
        host.apply([.show(.toast, display: 1, contentHeight: 0)])
        #expect(host.chrome.contentTransition == .fade)
        host.curves = IslandMotion(reduceMotion: false)
        host.apply([.show(.expanded, display: 1, contentHeight: 108)])
        #expect(host.chrome.contentTransition == .scaleAndFade(from: 0.96))
        host.close()
    }
}
