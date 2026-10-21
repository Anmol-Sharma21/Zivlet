import TestSupport
import Testing
import ZivletCore

@testable import ZivletTrigger

@Suite("TriggerMachine properties")
struct TriggerPropertyTests {
    static func randomEvents(seed: UInt64, count: Int, files: Bool) -> [TriggerEvent] {
        var rng = SplitMix64(seed: seed)
        let sources: [SampleSource] = [.mouseDown, .mouseDragged, .mouseUp, .frame, .flagsChanged]
        return (0..<count).map { i in
            if Int.random(in: 0..<10, using: &rng) == 0 {
                return [.escape, .spaceChanged, .dropHandled].randomElement(using: &rng)!
            }
            return T.sample(
                i * 9, sources.randomElement(using: &rng)!,
                mods: ModifierMask(rawValue: UInt8.random(in: 0...15, using: &rng)),
                down: Bool.random(using: &rng), cc: Int.random(in: 0...3, using: &rng), files: files)
        }
    }

    @Test(arguments: 0..<200)
    func neverShowsWithoutAFileDrag(seed: Int) {
        let run = T.run(Self.randomEvents(seed: UInt64(seed), count: 120, files: false))
        #expect(!run.effects.contains { $0.isShow })
    }

    @Test(arguments: 0..<200)
    func everyShowIsPairedWithAtMostOneOpenWheel(seed: Int) {
        let run = T.run(
            Self.randomEvents(seed: UInt64(seed), count: 120, files: true)
                + [.payload(changeCount: 1, summary: T.everyMode)])
        var open = false
        for effect in run.effects {
            switch effect {
            case .show:
                #expect(!open)
                open = true
            case .hide:
                #expect(open)
                open = false
            case .switchTo, .reject: #expect(open)
            default: break
            }
        }
    }
}
