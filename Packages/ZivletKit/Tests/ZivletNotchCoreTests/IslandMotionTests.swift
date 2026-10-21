import Testing
import ZivletNotchCore

@Suite("Island motion (D-N5)")
struct IslandMotionTests {
    @Test func springsWithoutReduceMotion() {
        #expect(IslandMotion(reduceMotion: false).expand == .spring(response: 0.38, damping: 0.78))
        #expect(IslandMotion(reduceMotion: false).collapse == .spring(response: 0.32, damping: 0.9))
    }

    @Test func onlyAFadeWithReduceMotion() {
        let motion = IslandMotion(reduceMotion: true)
        #expect(motion.expand == .fade(seconds: 0.18) && motion.collapse == .fade(seconds: 0.18))
    }
}
