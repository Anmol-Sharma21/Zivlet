import Foundation
import Testing

@testable import ZivletSettings

@Suite("Box settings (D-M5b-19)")
@MainActor
struct BoxSettingsTests {
    @Test func defaultsFollowTheOwnersChoices() throws {
        let box = SettingsStore(defaults: try freshDefaults()).current.box
        #expect(box.trayWhileDragging && !box.shakeToOpen && box.autoClear == .off && box.dropsGo == .recentBox)
        #expect(Settings.defaults.box == box)
    }

    @Test func theGroupRoundTripsUnderItsOwnKey() throws {
        let defaults = try freshDefaults()
        SettingsStore(defaults: defaults).update {
            $0.with(\.box.shakeToOpen, true).with(\.box.autoClear, .after24Hours).with(\.box.dropsGo, .newBox)
                .with(\.box.trayWhileDragging, false)
        }
        #expect(defaults.data(forKey: "settings.box.v1") != nil)
        let box = SettingsStore(defaults: defaults).current.box
        #expect(box.shakeToOpen && box.autoClear == .after24Hours && box.dropsGo == .newBox && !box.trayWhileDragging)
    }

    @Test func anM5aStoreLoadsTheDefaultsAndWritesNothingUntilAChange() throws {
        let defaults = try freshDefaults()
        let m5a = SettingsStore(defaults: defaults, launchArguments: [:])
        m5a.update { $0.with(\.hud.placement, .notch).with(\.feedback.sound, false) }
        let keys = ["trigger", "feedback", "output", "actions", "updates", "onboarding", "hud"].map {
            "settings.\($0).v1"
        }
        let before = keys.map { defaults.data(forKey: $0) }
        let reloaded = SettingsStore(defaults: defaults, launchArguments: [:])
        #expect(reloaded.current.box == BoxGroup() && defaults.object(forKey: "settings.box.v1") == nil)
        reloaded.update { $0.with(\.box.shakeToOpen, true) }
        #expect(keys.map { defaults.data(forKey: $0) } == before)
    }

    @Test func anUnknownStoredValueFallsBackToTheDefault() throws {
        let defaults = try freshDefaults()
        let json = #"{"trayWhileDragging":false,"shakeToOpen":true,"autoClear":"sometimes","dropsGo":"recentBox"}"#
        defaults.set(Data(json.utf8), forKey: "settings.box.v1")
        #expect(SettingsStore(defaults: defaults).current.box == BoxGroup())
    }

    @Test func diagnosticsListTheFourValues() throws {
        let json = Settings.defaults.diagnosticsJSON
        for key in ["\"box\"", "trayWhileDragging", "shakeToOpen", "autoClear", "dropsGo"] {
            #expect(json.contains(key))
        }
    }

    @Test func everyChoiceHasAStoredName() {
        #expect(BoxAutoClearChoice.allCases.map(\.rawValue) == ["off", "afterLeaving", "after24Hours"])
        #expect(BoxDropsChoice.allCases.map(\.rawValue) == ["recentBox", "newBox"])
    }
}
