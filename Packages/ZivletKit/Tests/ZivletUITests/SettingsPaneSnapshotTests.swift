import AppKit
import SwiftUI
import Testing
import ZivletActions

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
