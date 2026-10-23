import Foundation
import NotchTestSupport
import SwiftUI
import Testing
import ZivletNotch
import ZivletNotchCore
import ZivletSettings

@testable import ZivletUI

@Suite("Placement in Settings › General (design/19 §6)")
@MainActor
struct PlacementSettingsTests {
    @Test func theNotchChoiceIsNamedForTheMac() {
        #expect(PlacementCopy.notchLabel(hasBuiltInNotch: true) == "At the notch")
        #expect(PlacementCopy.notchLabel(hasBuiltInNotch: false) == "At the top of the screen")
        #expect(PlacementCopy.nearDropLabel == "Near the drop")
        #expect(PlacementCopy.title == "Show progress and results:")
        #expect(PlacementCopy.section == "Progress and results")
    }

    @Test func theSelectionShowsTheResolvedValueAndAChoiceIsStored() {
        let model = SettingsModel.preview
        model.hasBuiltInNotch = true
        #expect(model.shownPlacement == .notch)
        model.choosePlacement(.nearDrop)
        #expect(model.settings.hud.placement == .nearDrop && model.shownPlacement == .nearDrop)
    }

    @Test func automaticWithoutABuiltInNotchShowsNearTheDrop() {
        let model = SettingsModel.preview
        model.hasBuiltInNotch = false
        #expect(model.settings.hud.placement == .automatic && model.shownPlacement == .nearDrop)
    }

    @Test func withTheLidClosedTheLabelStaysAtTheNotch() throws {
        let provider = FakeDisplayProvider([try OffscreenDisplays.plain()], hasBuiltInNotch: true)
        let model = SettingsModel.preview
        model.follow(provider)
        #expect(model.hasBuiltInNotch && model.notchLabel == "At the notch")
    }

    @Test func theModelFollowsTheLatchWhenANotchDisplayAppears() async throws {
        let provider = FakeDisplayProvider([try OffscreenDisplays.plain()], hasBuiltInNotch: false)
        let model = SettingsModel.preview
        model.follow(provider)
        #expect(model.notchLabel == "At the top of the screen")
        provider.hasBuiltInNotch = true
        provider.set([try OffscreenDisplays.notch()])
        await ManualClock.settle()
        #expect(model.hasBuiltInNotch && model.notchLabel == "At the notch")
    }

    @Test func theGeneralPaneRendersWithTheNewSection() throws {
        let model = SettingsModel.preview
        model.hasBuiltInNotch = true
        let image = try #require(ImageRenderer(content: GeneralPane(model: model).frame(width: 520)).nsImage)
        #expect(image.size.width >= 480 && image.size.height >= 200)
    }

    @Test func theLaunchArgumentOverridesForOneRunAndIsNotStored() throws {
        let suite = "zivlet-placement-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let json = store.current.diagnosticsJSON
        let override = PlacementOverride.parse([PlacementOverride.key: "nearDrop"])
        #expect(override == .nearDrop)
        let route = PlacementOverride.defaultRoute(override: override, settings: store.current, hasBuiltInNotch: true)
        #expect(route == .nearDrop)
        #expect(store.current.hud.placement == .automatic && store.current.diagnosticsJSON == json)
        store.update { $0.with(\.hud.placement, .nearDrop) }
        #expect(SettingsStore(defaults: defaults).current.hud.placement == .nearDrop)
    }

    @Test func withoutAnOverrideTheDefaultRouteIsTheResolvedSetting() {
        #expect(PlacementOverride.parse([:]) == nil)
        #expect(PlacementOverride.parse([PlacementOverride.key: "sideways"]) == nil)
        #expect(PlacementOverride.parse([PlacementOverride.key: "notch"]) == .notch)
        let settings = Settings.defaults
        #expect(PlacementOverride.defaultRoute(override: nil, settings: settings, hasBuiltInNotch: true) == .notch)
        #expect(PlacementOverride.defaultRoute(override: nil, settings: settings, hasBuiltInNotch: false) == .nearDrop)
        #expect(PlacementOverride.defaultRoute(override: .notch, settings: settings, hasBuiltInNotch: false) == .notch)
    }
}
