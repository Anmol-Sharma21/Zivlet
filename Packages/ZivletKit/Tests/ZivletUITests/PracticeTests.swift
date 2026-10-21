import Foundation
import ImageIO
import TestSupport
import Testing
import ZivletCore
import ZivletWheelCore

@testable import ZivletUI

enum PracticeFx {
    static func selection(mode: WheelMode) -> WheelSelection {
        WheelSelection(mode: mode, target: .convert(.png), urls: [URL(filePath: "/tmp/practice.png")])
    }
}

@Suite("Practice: the real wheel, nothing converted (P1-47)")
@MainActor
struct PracticeTests {
    @Test func practiceSucceedsOnTheFirstSelectionOfTheTaughtMode() {
        let practice = PracticeState(teaching: .convert)
        #expect(practice.outcome == .waiting)
        #expect(practice.receiving(PracticeFx.selection(mode: .tools)).outcome == .wrongMode(expected: .convert))
        #expect(practice.receiving(PracticeFx.selection(mode: .convert)).outcome == .done)
    }

    @Test func thePracticePagesSwallowSelectionsAndSayWhatHappened() {
        let model = OnboardingModel.preview()
        #expect(!model.receive(PracticeFx.selection(mode: .convert)))  // welcome page: not practising
        model.show(.practiceConvert)
        #expect(model.practiceMessage == "Drag the sample and tap ⇧.")
        #expect(model.receive(PracticeFx.selection(mode: .actions)))
        #expect(model.practiceMessage == "That was the Actions wheel. Tap ⇧ for Convert.")
        #expect(model.receive(PracticeFx.selection(mode: .convert)))
        #expect(model.practiceMessage == "That's it.")
    }

    @Test func toolsThenActionsAreTaughtInTurn() {
        let model = OnboardingModel.preview()
        model.show(.practiceToolsActions)
        #expect(model.practiceMessage == "Drag the sample and tap ⌘.")
        _ = model.receive(PracticeFx.selection(mode: .tools))
        #expect(model.practiceMessage == "Now try ⌃ for Actions.")
        _ = model.receive(PracticeFx.selection(mode: .actions))
        #expect(model.practiceMessage == "That's it.")
    }

    @Test func leavingThePageStopsPractising() {
        let model = OnboardingModel.preview()
        model.show(.practiceConvert)
        model.next()
        model.next()
        #expect(!model.receive(PracticeFx.selection(mode: .convert)) && model.practiceMessage == nil)
    }
}

@Suite("Practice sample is Zivlet's own drawing (P1-47)")
struct OnboardingSampleTests {
    @Test func makesAReadablePNGOnce() throws {
        let dir = try TempDir()
        let first = try OnboardingSample.make(in: dir.url)
        let modified = try FileManager.default.attributesOfItem(atPath: first.path)[.modificationDate] as? Date
        let again = try OnboardingSample.make(in: dir.url)
        #expect(first == again)
        #expect(try FileManager.default.attributesOfItem(atPath: again.path)[.modificationDate] as? Date == modified)
        let source = try #require(CGImageSourceCreateWithURL(first as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.png")
        #expect(CGImageSourceGetCount(source) == 1)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 512 && image.height == 320)
    }

    @Test func anUnwritableFolderIsAnError() {
        #expect(throws: OnboardingSample.Failure.self) {
            try OnboardingSample.make(in: URL(filePath: "/dev/null/nope", directoryHint: .isDirectory))
        }
    }
}
