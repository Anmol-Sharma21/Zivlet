import AppKit
import Testing
import ZivletActions
import ZivletShelfCore

@testable import ZivletBox

@Suite("Share from the Drop Box (P2-142)")
@MainActor
struct BoxShareTests {
    @Test func shareShowsThePickerOnceWithTheTargetsAtTheShareButton() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(3)
        _ = await box.add(files, newBox: false)
        box.showPanel()
        box.press(.share)
        #expect(rig.picker.shown.count == 1)
        #expect(rig.picker.shown.first?.urls == files.map(\.standardizedFileURL))
        #expect(rig.picker.shown.first?.rect == BoxLook.Panel.shareAnchor && rig.picker.shown.first?.edge == .minY)
        #expect(rig.results.results.isEmpty)
        box.hidePanel()
    }

    @Test func theShareKeyActsOnTheSelectionOnly() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(3)
        _ = await box.add(files, newBox: false)
        box.showPanel()
        box.press(.select(box.viewModel.items[1].id, extend: false, toggle: false))
        #expect(box.handleKey(BoxKeyStroke(chars: "s", command: true)))
        #expect(rig.picker.shown.map(\.urls) == [[files[1].standardizedFileURL]])
        box.hidePanel()
    }

    @Test func withNothingPresentShareShowsTheFailureCardInstead() async throws {
        let rig = try BoxRig()
        let box = rig.controller()
        box.start()
        let files = try rig.files(2)
        _ = await box.add(files, newBox: false)
        for file in files {
            rig.bookmarks.resolutions[file.standardizedFileURL.path] = .failed(
                code: 4, storedVolumePath: nil, storedVolumeName: nil)
        }
        box.showPanel()
        box.press(.share)
        #expect(rig.picker.shown.isEmpty)
        #expect(
            rig.results.results == [
                .failed(
                    ActionCard(
                        title: "Nothing here can be shared.", lines: ["f0.txt is missing.", "f1.txt is missing."]))
            ])
        #expect(rig.results.anchors.first??.isEmpty == false)
        box.hidePanel()
    }
}
