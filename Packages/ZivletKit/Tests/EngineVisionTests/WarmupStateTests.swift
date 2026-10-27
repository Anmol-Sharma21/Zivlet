import CoreGraphics
import Synchronization
import Testing
import ZivletCore

@testable import EngineVision

@Suite("Warm-up state (P2-103, D-M6-16): once per OS build and language set, never looping within a launch")
struct WarmupStateTests {
    let hindi = TextWarmupRecord(osBuild: "26A1", languages: ["hi-Deva", "en-Latn"])

    @Test func aFreshInstallNeedsAWarmUp() {
        let state = WarmupState.initial(stored: nil, current: hindi)
        #expect(state.phase == .needed && state.shouldStart)
    }

    @Test func doneForTheSameBuildAndLanguagesNeedsNothing() {
        let state = WarmupState.initial(stored: hindi, current: hindi)
        #expect(state.phase == .done && !state.shouldStart)
    }

    @Test func anotherOSBuildNeedsItAgain() {
        let updated = TextWarmupRecord(osBuild: "26B5", languages: hindi.languages)
        #expect(WarmupState.initial(stored: hindi, current: updated).phase == .needed)
    }

    @Test func anotherLanguageSetNeedsItAgain() {
        let english = TextWarmupRecord(osBuild: "26A1", languages: ["en-Latn"])
        let state = WarmupState.initial(stored: hindi, current: hindi).changed(to: english)
        #expect(state.phase == .needed && state.shouldStart)
    }

    @Test func runningThenFinishedIsDoneWithTheRecordToStore() {
        let state = WarmupState.initial(stored: nil, current: hindi).started()
        #expect(state.phase == .running && !state.shouldStart)
        let done = state.finished()
        #expect(done.phase == .done && done.record == hindi)
    }

    @Test func anInterruptedWarmUpStaysNeededButIsNotRetriedThisLaunch() {
        let state = WarmupState.initial(stored: nil, current: hindi).started().interrupted()
        #expect(state.phase == .needed && !state.shouldStart)
        #expect(WarmupState.initial(stored: nil, current: hindi).shouldStart, "the next launch tries again")
    }

    @Test func aLanguageChangeAfterAnInterruptionMayTryOnce() {
        let english = TextWarmupRecord(osBuild: "26A1", languages: ["en-Latn"])
        let state = WarmupState.initial(stored: nil, current: hindi).started().interrupted().changed(to: english)
        #expect(state.shouldStart)
    }

    @Test func theSameRecordChangesNothing() {
        let state = WarmupState.initial(stored: hindi, current: hindi)
        #expect(state.changed(to: hindi) == state)
    }

    @Test func theRecordNamesTheLanguagesInOrder() {
        let record = TextWarmupRecord(osBuild: "x", languages: [LanguageTag.hindi, .english])
        #expect(record.languages == ["hi-Deva", "en-Latn"])
    }
}

@Suite("Vision warm-up (D-M6-16): three sizes in the production configuration")
struct VisionWarmupTests {
    @Test func threeImagesAreRecognisedWithTheLanguages() async throws {
        let recognizer = RecordingRecognizer()
        try await VisionWarmup.run(recognizer: recognizer, languages: [.hindi, .english])
        #expect(
            recognizer.sizes.withLock { $0 } == [
                CGSize(width: 64, height: 64), CGSize(width: 1024, height: 1024), CGSize(width: 2550, height: 3300),
            ])
    }

    @Test func aCancelledWarmUpStops() async throws {
        let recognizer = RecordingRecognizer()
        let task = Task {
            try? await Task.sleep(for: .seconds(5))
            try await VisionWarmup.run(recognizer: recognizer, languages: [.english])
        }
        task.cancel()
        await #expect(throws: TextError.cancelled) { try await task.value }
        #expect(recognizer.calls == 0)
    }

    @Test func theImagesCarryTextInEachScript() throws {
        let images = try VisionWarmup.images(languages: [.hindi, .english])
        #expect(images.count == 3)
        #expect(VisionWarmup.lines(for: [.hindi, .english]).count == 2)
        #expect(VisionWarmup.lines(for: [.english]).count == 1)
    }
}
