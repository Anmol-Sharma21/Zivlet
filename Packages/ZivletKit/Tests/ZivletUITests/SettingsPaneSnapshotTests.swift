import AppKit
import SwiftUI
import Testing
import ZivletActions
import ZivletSettings

@testable import ZivletUI

@Suite("Settings panes render (D3)")
@MainActor
struct SettingsPaneSnapshotTests {
    @Test(arguments: SettingsPane.allCases)
    func everyPaneRendersWithDefaults(pane: SettingsPane) throws {
        let image = try #require(ImageRenderer(content: pane.view(model: .preview)).nsImage)
        #expect(image.size.width >= 480 && image.size.height >= 200)
    }

    @Test func generalPaneListsOnlyInstalledTerminals() {
        let model = SettingsModel.preview(installedTerminals: [.terminal, .ghostty])
        #expect(model.terminalChoices.map(\.name) == ["Terminal", "Ghostty"])
    }

    /// The Drop Box rows of 19c §5 (D-M5b-19 defaults), in Zivlet's words.
    @Test func generalPaneHasTheDropBoxRows() {
        #expect(DropBoxSection.title == "Drop Box")
        #expect(
            DropBoxSection.trayLabel == "Open at the notch while dragging"
                && DropBoxSection.shakeLabel == "Shake to open")
        #expect(DropBoxSection.clearLabel == "Clear items" && DropBoxSection.dropsLabel == "New drops go to")
        #expect(
            BoxAutoClearChoice.allCases.map(DropBoxSection.label) == [
                "Never", "After they leave the box", "After 24 hours",
            ])
        #expect(BoxDropsChoice.allCases.map(DropBoxSection.label) == ["The last box", "A new box"])
        let image = ImageRenderer(content: Form { DropBoxSection(model: .preview) }.frame(width: 520)).nsImage
        #expect((image?.size.height ?? 0) > 100)
    }

    /// Box storage and Empty Box Storage (19c §5, OWN-APP-3): the overflow menu's line, in Settings too.
    @Test func generalPaneShowsBoxStorageAndEmptiesIt() throws {
        var bytes: Int64 = 1_200_000_000
        var emptied = 0
        let commands = SettingsCommands(
            write: { $0(.defaults) }, boxStorage: { bytes },
            emptyBoxStorage: {
                emptied += 1
                bytes = 0
            })
        let model = SettingsModel(settings: .defaults, installedTerminals: [.terminal], commands: commands)
        #expect(model.boxStorageBytes == nil)
        model.refreshBoxStorage()
        #expect(model.boxStorageBytes == 1_200_000_000 && DropBoxSection.storageValue(1_200_000_000) == "1.2 GB")
        #expect(DropBoxSection.storageLabel == "Box storage" && DropBoxSection.emptyLabel == "Empty Box Storage")
        #expect(DropBoxSection.emptyQuestion == "Empty box storage?" && DropBoxSection.emptyAnswer == "Empty")
        let image = ImageRenderer(content: Form { DropBoxSection(model: model) }.frame(width: 520)).nsImage
        #expect((image?.size.height ?? 0) > 100)
        model.emptyBoxStorage()
        #expect(emptied == 1 && model.boxStorageBytes == 0)
    }

    @Test func paneTitlesAreZivletsOwn() {
        #expect(SettingsPane.allCases.map(\.title) == ["General", "Updates", "Advanced"])
    }

    #if DEBUG
        @Test func theDemoArgumentNamesAPane() {
            #expect(SettingsPane.demo(arguments: ["Z", "-ZivletDemoSettings", "updates"]) == .updates)
            #expect(SettingsPane.demo(arguments: ["Z", "-ZivletDemoSettings", "formats"]) == nil)
            #expect(SettingsPane.demo(arguments: ["Z", "-ZivletDemoSettings"]) == nil)
            #expect(SettingsPane.demo(arguments: ["Z"]) == nil)
        }
    #endif

    @Test func theFolderLineShortensTheHomeFolder() {
        #expect(GeneralPane.folderName(NSHomeDirectory() + "/Downloads") == "~/Downloads")
        #expect(GeneralPane.folderName("/Volumes/Card") == "/Volumes/Card")
    }

    @Test func theWindowHasOneTabPerPane() throws {
        let controller = SettingsWindowController(model: .preview)
        let tabs = try #require(controller.contentViewController as? NSTabViewController)
        #expect(tabs.tabViewItems.map(\.label) == ["General", "Updates", "Advanced"])
        controller.show(.advanced)
        #expect(tabs.selectedTabViewItemIndex == 2 && controller.window?.title == "Advanced")
        controller.close()
    }
}
