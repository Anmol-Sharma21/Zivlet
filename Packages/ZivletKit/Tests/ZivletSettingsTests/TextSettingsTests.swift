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

    @Test func theLanguageChoiceDefaultsToMatchMyLanguages() throws {
        #expect(SettingsStore(defaults: try freshDefaults()).current.text.language == .matchMine)
    }

    @Test func theLanguageChoiceRoundTrips() throws {
        let defaults = try freshDefaults()
        SettingsStore(defaults: defaults).update { $0.with(\.text.language, .hindiAndEnglish) }
        #expect(SettingsStore(defaults: defaults).current.text.language == .hindiAndEnglish)
    }

    @Test func anUnknownLanguageFallsBackToTheDefaultAndKeepsTheWarmUp() throws {
        let defaults = try freshDefaults()
        let json = #"{"language":"klingon","warmed":{"osBuild":"26A1","languages":["en-Latn"]}}"#
        defaults.set(Data(json.utf8), forKey: "settings.text.v1")
        let text = SettingsStore(defaults: defaults).current.text
        #expect(text.language == .matchMine)
        #expect(text.warmed == TextWarmupRecord(osBuild: "26A1", languages: ["en-Latn"]))
    }

    @Test func aStoreWithoutTheLanguageReadsTheDefault() throws {
        let defaults = try freshDefaults()
        defaults.set(Data(#"{"warmed":{"osBuild":"26A1","languages":["en-Latn"]}}"#.utf8), forKey: "settings.text.v1")
        #expect(SettingsStore(defaults: defaults).current.text.language == .matchMine)
    }

    /// D14: the stored group holds the choice and the warm-up record, nothing else.
    @Test func theStoredGroupHoldsOnlyTheChoiceAndTheRecord() throws {
        var group = TextGroup()
        group.warmed = TextWarmupRecord(osBuild: "26A1", languages: ["hi-Deva"])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(group)) as? [String: Any]
        #expect(Set(json?.keys.map { $0 } ?? []) == ["language", "warmed"])
    }

    @Test func diagnosticsListTheGroupWithoutAnyText() {
        #expect(Settings.defaults.diagnosticsJSON.contains("\"text\""))
    }
}
