import Foundation
import Testing

@testable import ZivletSettings

@Suite("HUD placement setting (OWN-HUD-1, design/19 §6)")
@MainActor
struct HUDPlacementTests {
    // Each test uses `freshDefaults()` from SettingsStoreTests: a private suite, never `.standard`.

    @Test func anM4StoreLoadsWithAutomaticPlacementAndUnchangedGroups() throws {
        let defaults = try freshDefaults()
        let m4 = SettingsStore(defaults: defaults, launchArguments: [:])
        m4.update { $0.with(\.output.revealResults, false) }
        defaults.removeObject(forKey: "settings.hud.v1")  // what an M4 install has
        let reloaded = SettingsStore(defaults: defaults, launchArguments: [:])
        #expect(reloaded.current.hud.placement == .automatic)
        #expect(reloaded.current.output.revealResults == false)
        #expect(defaults.object(forKey: "settings.hud.v1") == nil)  // nothing is written until the person picks
    }

    @Test func theOtherGroupsStayByteIdenticalWhenTheChoiceIsSaved() throws {
        let defaults = try freshDefaults()
        let m4 = SettingsStore(defaults: defaults, launchArguments: [:])
        m4.update { $0.with(\.output.revealResults, false).with(\.feedback.sound, false).with(\.onboarding.page, 3) }
        let keys = ["trigger", "feedback", "output", "actions", "updates", "onboarding"].map { "settings.\($0).v1" }
        let before = keys.map { defaults.data(forKey: $0) }
        SettingsStore(defaults: defaults, launchArguments: [:]).update { $0.with(\.hud.placement, .notch) }
        #expect(keys.map { defaults.data(forKey: $0) } == before)
    }

    @Test func automaticResolvesToTheNotchOnlyWithABuiltInNotch() {
        #expect(HUDPlacement.automatic.resolved(hasBuiltInNotch: true) == .notch)
        #expect(HUDPlacement.automatic.resolved(hasBuiltInNotch: false) == .nearDrop)
        #expect(HUDPlacement.nearDrop.resolved(hasBuiltInNotch: true) == .nearDrop)
        #expect(HUDPlacement.notch.resolved(hasBuiltInNotch: false) == .notch)  // the pill on that Mac
    }

    @Test func anExplicitChoiceIsStoredAndReloaded() throws {
        let defaults = try freshDefaults()
        SettingsStore(defaults: defaults, launchArguments: [:]).update { $0.with(\.hud.placement, .nearDrop) }
        #expect(defaults.data(forKey: "settings.hud.v1") != nil)
        #expect(SettingsStore(defaults: defaults, launchArguments: [:]).current.hud.placement == .nearDrop)
    }

    @Test func anUnreadableGroupFallsBackToAutomatic() throws {
        let defaults = try freshDefaults()
        defaults.set(Data(#"{"placement":"corner"}"#.utf8), forKey: "settings.hud.v1")
        #expect(SettingsStore(defaults: defaults, launchArguments: [:]).current.hud.placement == .automatic)
    }

    @Test func diagnosticsIncludeThePlacement() {
        let json = Settings().diagnosticsJSON
        #expect(json.contains("\"hud\"") && json.contains("\"placement\" : \"automatic\""))
    }
}
