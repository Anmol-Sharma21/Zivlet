import DragTraceSupport
import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import ZivletTrigger

@Suite("Shake detector (P2-141, D-M5b-15)")
struct ShakeDetectorTests {
    /// A shake at 6 Hz, ± 60 pt, starting at once: its fourth reversal comes about 0.3 s in.
    private func quickShake(halfCycles: Double = 4) -> [InputSample] {
        let points = (0...Int(halfCycles / 12 * SyntheticDrags.rate) + 12).map { frame in
            let t = Double(frame) / SyntheticDrags.rate
            return Point2D(x: 900 + 60 * sin(2 * .pi * 6 * min(t, halfCycles / 12)), y: 500)
        }
        return SyntheticDrags.samples(from: points)
    }

    @Test func syntheticShakesFire() {
        var rng = SplitMix64(seed: 141)
        let fired = (0..<500).filter { _ in ShakeDetector.fires(on: SyntheticDrags.shake(&rng)) }
        #expect(fired.count == 500)
    }

    @Test(arguments: SyntheticDrags.NonShake.allCases)
    func ordinaryDragsDoNot(_ kind: SyntheticDrags.NonShake) {
        var rng = SplitMix64(seed: 55)
        let fired = (0..<500).filter { _ in ShakeDetector.fires(on: SyntheticDrags.trace(kind, &rng)) }
        #expect(fired.isEmpty)
    }

    @Test func threeReversalsAreNotAShake() {
        #expect(!ShakeDetector.fires(on: quickShake(halfCycles: 3)))
        #expect(ShakeDetector.fires(on: quickShake(halfCycles: 4)))
    }

    @Test func smallSwingsAreNotAShake() {
        let points = (0..<120).map { Point2D(x: 900 + 14 * sin(2 * .pi * 5 * Double($0) / 120), y: 500) }
        #expect(!ShakeDetector.fires(on: SyntheticDrags.samples(from: points)))
    }

    @Test func reversalsSpreadOverMoreThanTheWindowAreNotAShake() {
        let points = (0..<240).map { Point2D(x: 900 + 60 * sin(2 * .pi * 2 * Double($0) / 120), y: 500) }
        #expect(!ShakeDetector.fires(on: SyntheticDrags.samples(from: points)))
    }

    @Test func nothingFiresJustAfterTheWheelCloses() {
        let samples = quickShake()
        let detector = ShakeDetector().wheelHidden(at: samples[0].uptime)
        #expect(!detector.fires(on: samples))
        #expect(ShakeDetector().wheelHidden(at: samples[0].uptime - .seconds(1)).fires(on: samples))
    }

    @Test func theWheelClosingForgetsTheReversalsBeforeIt() {
        var rng = SplitMix64(seed: 3)
        for _ in 0..<100 {
            let samples = SyntheticDrags.shake(&rng)
            guard let firing = firstFiring(ShakeDetector(), samples) else {
                Issue.record("a synthetic shake did not fire")
                return
            }
            let closed = ShakeDetector().wheelHidden(at: samples[firing].uptime - .milliseconds(1))
            #expect(!closed.fires(on: samples))
        }
    }

    @Test func aSecondShakeInTheSameDragDoesNotFireAgain() {
        let shake = quickShake()
        let twice = SyntheticDrags.samples(from: (shake + shake).map(\.location))
        let (latched, fires) = run(ShakeDetector(), twice)
        #expect(fires == 1 && latched.hasFired)
        #expect(run(latched.reset(), shake).fires == 1)
    }

    @Test func theDefaultsAreTheDecidedOnes() {
        let config = ShakeDetector.Config()
        #expect(config.reversals == 4 && config.minAmplitude == 30)
        #expect(config.window == .milliseconds(600) && config.cooldown == .milliseconds(300))
    }

    @Test func recordedNormalDragsNeverShake() throws {
        guard let folder = RecordedDrags.folder else { return }  // the owner's run (OS-M5b-1), not CI
        let loaded = try DragTraceFolder.load(from: folder)
        #expect(loaded.invalid.isEmpty, "refused: \(loaded.invalid.map { "\($0.name): \($0.reason)" })")
        let normal = loaded.traces.map(\.trace).filter { $0.label == .normal }
        let shaking = normal.filter { ShakeDetector.fires(on: $0.inputSamples) }
        #expect(shaking.isEmpty, "\(shaking.count) of \(normal.count) recorded normal drags fired")
    }

    private func run(_ start: ShakeDetector, _ samples: [InputSample]) -> (ShakeDetector, fires: Int) {
        samples.reduce((start, 0)) { state, sample in
            let (next, fired) = state.0.observing(sample)
            return (next, state.1 + (fired ? 1 : 0))
        }
    }

    private func firstFiring(_ start: ShakeDetector, _ samples: [InputSample]) -> Int? {
        var detector = start
        for (index, sample) in samples.enumerated() {
            let (next, fired) = detector.observing(sample)
            if fired { return index }
            detector = next
        }
        return nil
    }
}
