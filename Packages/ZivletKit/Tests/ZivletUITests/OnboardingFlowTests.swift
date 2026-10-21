import Foundation
import SwiftUI
import TestSupport
import Testing
import ZivletCore
import ZivletSettings
import ZivletTrigger

@testable import ZivletUI

@Suite("Onboarding flow (P1-47, 03b §8.2)")
struct OnboardingFlowTests {
    @Test func walksForwardAndBackWithinBounds() {
        let flow = OnboardingFlow(page: .welcome)
        #expect(flow.back().page == .welcome)
        #expect(flow.next().next().page == .practiceToolsActions)
        #expect(OnboardingFlow(page: .location).next().page == .location)
        #expect(OnboardingFlow(page: .welcome).isFirst && OnboardingFlow(page: .location).isLast)
    }

    @Test func onlyFinishCompletes() {
        let atEnd = OnboardingFlow(page: .location)
        #expect(!atEnd.next().isCompleted)
        #expect(atEnd.finish().isCompleted)
    }

    @Test func resumesAtTheStoredPage() {
        #expect(OnboardingFlow(storedPage: 3).page == .keyboard)
        #expect(OnboardingFlow(storedPage: 99).page == .welcome)
        #expect(OnboardingFlow(storedPage: -1).page == .welcome)
        #expect(OnboardingPage.allCases.count == OnboardingGroup.pageCount)
    }
}

@Suite("Onboarding model: paging is stored, finish completes (P1-47)")
@MainActor
struct OnboardingModelTests {
    @Test func pagingStoresThePageAndFinishWritesCompletedOnce() {
        var writes: [ZivletSettings.Settings] = []
        let model = OnboardingModel.preview { writes.append($0) }
        model.next()
        model.next()
        #expect(model.flow.page == .practiceToolsActions && writes.last?.onboarding.page == 2)
        model.back()
        #expect(writes.last?.onboarding.page == 1 && writes.last?.onboarding.completed == false)
        model.finish()
        #expect(writes.last?.onboarding.completed == true && model.flow.isCompleted)
    }

    /// Practice can be reopened from the menu after onboarding; Finish must not turn back on a login item the
    /// person turned off in Settings.
    @Test func reopenedAfterCompletionTheLoginChoiceIsTheCurrentState() {
        let commands = OnboardingCommands(write: { transform in transform(.defaults) })
        let done = Settings.defaults.with(\.onboarding.completed, true)
        #expect(!OnboardingModel(settings: done, commands: commands, loginItemIsOn: false).wantsLoginItem)
        #expect(OnboardingModel(settings: done, commands: commands, loginItemIsOn: true).wantsLoginItem)
        #expect(OnboardingModel(settings: .defaults, commands: commands, loginItemIsOn: false).wantsLoginItem)
    }

    @Test func keyCapsFollowTheBindings() throws {
        let bindings = try TriggerBindings(convert: .option, tools: .command, actions: .control)
        let model = OnboardingModel.preview(settings: Settings.defaults.with(\.trigger.bindings, bindings))
        #expect(model.keyCap(for: .convert) == "⌥" && model.keyCap(for: .actions) == "⌃")
    }
}

@Suite("Onboarding pages render (P1-47)")
@MainActor
struct OnboardingSnapshotTests {
    @Test(arguments: OnboardingPage.allCases)
    func everyPageRenders(page: OnboardingPage) throws {
        let model = OnboardingModel.preview()
        model.show(page)
        let image = try #require(ImageRenderer(content: OnboardingView(model: model)).nsImage)
        #expect(image.size == CGSize(width: 720, height: 480))
    }

    @Test func theWindowIsTheOnboardingSize() {
        let controller = OnboardingWindowController(model: .preview())
        #expect(controller.window?.contentLayoutRect.size == CGSize(width: 720, height: 480))
        #expect(controller.window?.title == "Welcome to Zivlet")
    }
}

@Suite("Location page: move out of a disk image (03b §8.2 page 7)")
struct AppLocationTests {
    @Test(arguments: [
        ("/Volumes/Zivlet/Zivlet.app", true),
        ("/private/var/folders/x/AppTranslocation/ABC/d/Zivlet.app", true),
        ("/Applications/Zivlet.app", false),
        ("/Users/me/Applications/Zivlet.app", false),
    ])
    func movingIsOfferedFromADiskImageOrTranslocation(path: String, offered: Bool) {
        #expect(AppLocation.needsMove(bundlePath: path) == offered)
    }

    @Test func copyingNeverReplacesAnExistingCopy() throws {
        let dir = try TempDir()
        let bundle = try dir.folder("Image/Zivlet.app")
        try dir.file("Image/Zivlet.app/Contents/Info.plist")
        let apps = try dir.folder("Applications")
        let copied = try AppLocation.copy(bundle: bundle, into: apps)
        #expect(FileManager.default.fileExists(atPath: copied.appending(path: "Contents/Info.plist").path))
        #expect(throws: AppLocation.MoveFailure.alreadyThere) { try AppLocation.copy(bundle: bundle, into: apps) }
        #expect(throws: AppLocation.MoveFailure.copyFailed) {
            try AppLocation.copy(bundle: dir.url.appending(path: "Missing.app"), into: apps)
        }
        #expect(AppLocation.MoveFailure.copyFailed.message.hasPrefix("Zivlet couldn't copy itself"))
    }

    /// A copy that fails part-way leaves nothing in Applications, so a retry is not told "already there".
    @Test func aFailedCopyLeavesNothingBehind() async throws {
        let dir = try TempDir()
        let bundle = try dir.folder("Image/Zivlet.app")
        try dir.file("Image/Zivlet.app/Contents/Info.plist")
        let locked = try dir.file("Image/Zivlet.app/Contents/Resources/locked.bin")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        let apps = try dir.folder("Applications")
        await #expect(throws: AppLocation.MoveFailure.copyFailed) {
            try await AppLocation.copyInBackground(bundle: bundle, into: apps)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: apps.path).isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
        let copied = try await AppLocation.copyInBackground(bundle: bundle, into: apps)
        #expect(try FileManager.default.contentsOfDirectory(atPath: apps.path) == ["Zivlet.app"])
        #expect(FileManager.default.fileExists(atPath: copied.appending(path: "Contents/Resources/locked.bin").path))
    }

    /// LaunchServices can hand back the running copy (same bundle id) or nothing; only a new process lets this one
    /// quit.
    @Test func thisCopyQuitsOnlyWhenAnotherProcessStarted() {
        #expect(!AppLocation.shouldQuit(launched: nil, current: 500))
        #expect(!AppLocation.shouldQuit(launched: 500, current: 500))
        #expect(AppLocation.shouldQuit(launched: 501, current: 500))
        #expect(AppLocation.MoveFailure.notOpened.message.contains("Applications"))
    }
}

@Suite("Location page: the move runs off the main actor (03b §8.2 page 7)")
@MainActor
struct MoveToApplicationsModelTests {
    @Test func theButtonWaitsForTheMoveAndShowsItsSentence() async {
        var stored = Settings.defaults
        let commands = OnboardingCommands(
            write: { transform in
                stored = transform(stored)
                return stored
            },
            moveToApplications: {
                try? await Task.sleep(for: .milliseconds(20))
                return "Zivlet couldn't copy itself to Applications."
            })
        let model = OnboardingModel(settings: .defaults, commands: commands)
        model.moveToApplications()
        #expect(model.isMoving)
        model.moveToApplications()  // ignored while the first move runs
        await model.moving?.value
        #expect(!model.isMoving && model.moveError == "Zivlet couldn't copy itself to Applications.")
    }
}
