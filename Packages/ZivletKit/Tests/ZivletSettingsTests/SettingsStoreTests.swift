import Foundation
import Testing
import ZivletTrigger

@testable import ZivletSettings

/// A fresh, empty defaults domain per test.
func freshDefaults() throws -> UserDefaults {
    let name = "zivlet-settings-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Settings store: defaults, validation, migration (D1, 03b §8.1)")
@MainActor
struct SettingsStoreTests {
    /// Copy Diagnostics (P1-48) shows the settings as JSON with plain slashes, so redaction can find the paths.
    @Test func diagnosticsJSONHasEveryGroupAndPlainSlashes() throws {
        let json = Settings.defaults.with(\.output.fallbackFolder, "/Users/someone/Exports").diagnosticsJSON
        for group in ["trigger", "feedback", "output", "actions", "updates", "onboarding"] {
            #expect(json.contains("\"\(group)\""))
        }
        #expect(json.contains("/Users/someone/Exports") && !json.contains(#"\/"#))
        #expect(try JSONSerialization.jsonObject(with: Data(json.utf8)) is [String: Any])
    }

    @Test func freshStoreHasTheDocumentedDefaults() throws {
        let settings = SettingsStore(defaults: try freshDefaults()).current
        #expect(settings.feedback.sound && settings.feedback.haptics && settings.feedback.theme == .glass)
        #expect(settings.output.revealResults)
        #expect(settings.output.fallbackFolder == URL.downloadsDirectory.path)
        #expect(settings.actions.terminal == "com.apple.Terminal")
        #expect(settings.trigger.bindings == .standard && settings.trigger.retapClosesWheel)
        #expect(!settings.trigger.honorsModifierHeldAtDragStart && !settings.trigger.paused)
        #expect(settings.updates.automaticChecks && !settings.updates.automaticDownloads)
        #expect(!settings.onboarding.completed && settings.onboarding.page == 0)
        #expect(settings.onboarding.practiceDragsLeft == 3)
    }

    @Test func updatesPersistAcrossStores() throws {
        let defaults = try freshDefaults()
        SettingsStore(defaults: defaults).update { $0.with(\.feedback.sound, false) }
        #expect(!SettingsStore(defaults: defaults).current.feedback.sound)
    }

    @Test func onlyChangedGroupsAreWritten() throws {
        let defaults = try freshDefaults()
        SettingsStore(defaults: defaults).update { $0.with(\.onboarding.page, 2) }
        #expect(defaults.data(forKey: "settings.onboarding.v1") != nil)
        #expect(defaults.data(forKey: "settings.feedback.v1") == nil)
    }

    @Test func anInvalidGroupFallsBackToItsDefaultOnly() throws {
        let defaults = try freshDefaults()
        defaults.set(Data(#"{"terminal":"bad id; rm -rf"}"#.utf8), forKey: "settings.actions.v1")
        defaults.set(Data(#"{"sound":false,"haptics":true,"theme":"solid"}"#.utf8), forKey: "settings.feedback.v1")
        let settings = SettingsStore(defaults: defaults).current
        #expect(settings.actions.terminal == "com.apple.Terminal")
        #expect(!settings.feedback.sound && settings.feedback.theme == .solid)
    }

    @Test func unreadableJSONFallsBackToTheDefault() throws {
        let defaults = try freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "settings.updates.v1")
        defaults.set("a string, not data", forKey: "settings.output.v1")
        let settings = SettingsStore(defaults: defaults).current
        #expect(settings.updates == UpdatesGroup())
        #expect(settings.output.revealResults)
    }

    @Test func duplicateModifierBindingsAreRefused() throws {
        let defaults = try freshDefaults()
        let json =
            #"{"bindings":{"convert":"shift","tools":"shift","actions":"control"},"#
            + #""retapClosesWheel":false,"honorsModifierHeldAtDragStart":false,"paused":false}"#
        defaults.set(Data(json.utf8), forKey: "settings.trigger.v1")
        let trigger = SettingsStore(defaults: defaults).current.trigger
        #expect(trigger.bindings == .standard && trigger.retapClosesWheel)
    }

    @Test func storedBindingsRoundTrip() throws {
        let defaults = try freshDefaults()
        let swapped = try TriggerBindings(convert: .command, tools: .shift, actions: .option)
        SettingsStore(defaults: defaults).update { $0.with(\.trigger.bindings, swapped) }
        #expect(SettingsStore(defaults: defaults).current.trigger.bindings == swapped)
    }

    @Test func aFallbackFolderThatIsNotAnExistingDirectoryIsRefused() throws {
        let defaults = try freshDefaults()
        let store = SettingsStore(defaults: defaults)
        store.update { $0.with(\.output.fallbackFolder, "relative/path") }
        #expect(store.current.output.fallbackFolder == URL.downloadsDirectory.path)
        store.update { $0.with(\.output.fallbackFolder, "/no/such/folder-\(UUID().uuidString)") }
        #expect(store.current.output.fallbackFolder == URL.downloadsDirectory.path)
        store.update { $0.with(\.output.fallbackFolder, NSTemporaryDirectory()) }
        #expect(store.current.output.fallbackFolder == NSTemporaryDirectory())
    }

    @Test func anInvalidUpdateIsDroppedForThatGroupOnly() throws {
        let store = SettingsStore(defaults: try freshDefaults())
        store.update { $0.with(\.actions.terminal, "x y").with(\.feedback.haptics, false) }
        #expect(store.current.actions.terminal == "com.apple.Terminal")
        #expect(!store.current.feedback.haptics)
    }

    @Test func onboardingCountersAreKeptInRange() throws {
        let defaults = try freshDefaults()
        defaults.set(
            Data(#"{"completed":false,"page":-4,"practiceDragsLeft":40}"#.utf8), forKey: "settings.onboarding.v1")
        #expect(SettingsStore(defaults: defaults).current.onboarding == OnboardingGroup())
    }

    @Test func theM3RevealKeyIsMigratedOnce() throws {
        let defaults = try freshDefaults()
        defaults.set(false, forKey: "ZivletRevealResults")
        #expect(!SettingsStore(defaults: defaults).current.output.revealResults)
        #expect(defaults.object(forKey: "ZivletRevealResults") == nil)
        #expect(!SettingsStore(defaults: defaults).current.output.revealResults)
    }

    @Test func aLaunchArgumentOverrideIsNotMigrated() throws {
        let defaults = try freshDefaults()
        defaults.set(false, forKey: "ZivletRevealResults")
        let store = SettingsStore(defaults: defaults, launchArguments: ["ZivletRevealResults": "NO"])
        #expect(store.current.output.revealResults)
        #expect(defaults.data(forKey: "settings.output.v1") == nil)
    }

    @Test func changesAreStreamed() async throws {
        let store = SettingsStore(defaults: try freshDefaults())
        var iterator = store.changes.makeAsyncIterator()
        store.update { $0.with(\.feedback.haptics, false) }
        #expect(await iterator.next()?.feedback.haptics == false)
    }

    @Test func everySubscriberSeesAChangeAndANoOpUpdateSendsNothing() async throws {
        let store = SettingsStore(defaults: try freshDefaults())
        var first = store.changes.makeAsyncIterator()
        var second = store.changes.makeAsyncIterator()
        store.update { $0 }
        store.update { $0.with(\.trigger.paused, true) }
        #expect(await first.next()?.trigger.paused == true)
        #expect(await second.next()?.trigger.paused == true)
    }
}

@Suite("Settings → trigger configuration (D2)")
struct TriggerGroupConfigTests {
    @Test func theTriggerGroupBecomesTheMachineConfig() throws {
        let bindings = try TriggerBindings(convert: .control, tools: .command, actions: .shift)
        var group = TriggerGroup()
        group.bindings = bindings
        group.retapClosesWheel = false
        group.honorsModifierHeldAtDragStart = true
        let config = group.config
        #expect(config.bindings == bindings && !config.retapClosesWheel && config.honorsModifierHeldAtDragStart)
        #expect(config.detectionWindow == TriggerConfig().detectionWindow)
    }
}
