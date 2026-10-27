import Foundation
import Testing
import ZivletCore

@testable import ZivletSettings

@Suite("Text recognition settings (P2-103, plan 18d D7): what the warm-up was done for")
@MainActor
struct TextSettingsTests {
    @Test func nothingIsWarmedByDefault() throws {
        #expect(SettingsStore(defaults: try freshDefaults()).current.text.warmed == nil)
        #expect(Settings.defaults.text == TextGroup())
    }

    @Test func theWarmedRecordRoundTripsUnderItsOwnKey() throws {
        let defaults = try freshDefaults()
        let record = TextWarmupRecord(osBuild: "26A1", languages: ["hi-Deva", "en-Latn"])
        SettingsStore(defaults: defaults).update { $0.with(\.text.warmed, record) }
        #expect(defaults.data(forKey: "settings.text.v1") != nil)
        #expect(SettingsStore(defaults: defaults).current.text.warmed == record)
    }

    @Test func aRecordWithAnEmptyBuildOrNoLanguagesIsRefused() throws {
        let store = SettingsStore(defaults: try freshDefaults())
        store.update { $0.with(\.text.warmed, TextWarmupRecord(osBuild: "", languages: ["en-Latn"])) }
        store.update { $0.with(\.text.warmed, TextWarmupRecord(osBuild: "26A1", languages: [])) }
        #expect(store.current.text.warmed == nil)
    }

    @Test func anUnreadableStoredGroupFallsBackToTheDefault() throws {
        let defaults = try freshDefaults()
        defaults.set(Data(#"{"warmed":{"osBuild":3}}"#.utf8), forKey: "settings.text.v1")
        #expect(SettingsStore(defaults: defaults).current.text == TextGroup())
    }

    @Test func diagnosticsListTheGroupWithoutAnyText() {
        #expect(Settings.defaults.diagnosticsJSON.contains("\"text\""))
    }
}
