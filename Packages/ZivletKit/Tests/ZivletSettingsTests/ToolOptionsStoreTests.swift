import Foundation
import Testing
import ZivletCore

@testable import ZivletSettings

/// A tool's options as a 2B tool would keep them.
struct SpeedOptions: RememberedToolOptions {
    static let defaults = SpeedOptions(factor: 1, keepsPitch: true)
    let factor: Double
    let keepsPitch: Bool
}

@Suite("Tool options remembered per tool (P2-30, plan 20b A4)")
@MainActor
struct ToolOptionsStoreTests {
    @Test func optionsComeBackAsTheyWereSaved() throws {
        let defaults = try freshDefaults()
        let saved = SpeedOptions(factor: 1.5, keepsPitch: false)
        ToolOptionsStore(defaults: defaults).save(saved, for: .videoSpeed)
        #expect(ToolOptionsStore(defaults: defaults).load(SpeedOptions.self, for: .videoSpeed) == saved)
    }

    @Test func eachToolHasItsOwnOptions() throws {
        let store = ToolOptionsStore(defaults: try freshDefaults())
        store.save(SpeedOptions(factor: 2, keepsPitch: true), for: .videoSpeed)
        #expect(store.load(SpeedOptions.self, for: .audioTrim) == .defaults)
    }

    @Test func aMissingOrUnreadableValueGivesTheToolsDefaults() throws {
        let defaults = try freshDefaults()
        let store = ToolOptionsStore(defaults: defaults)
        #expect(store.load(SpeedOptions.self, for: .videoSpeed) == .defaults)
        defaults.set(Data("not json".utf8), forKey: ToolOptionsStore.key(for: .videoSpeed))
        #expect(store.load(SpeedOptions.self, for: .videoSpeed) == .defaults)
        defaults.set("a string", forKey: ToolOptionsStore.key(for: .videoSpeed))
        #expect(store.load(SpeedOptions.self, for: .videoSpeed) == .defaults)
    }

    @Test func savingWritesOnlyTheToolsOwnKey() throws {
        let defaults = try freshDefaults()
        let before = Set(defaults.dictionaryRepresentation().keys)
        ToolOptionsStore(defaults: defaults).save(SpeedOptions(factor: 3, keepsPitch: true), for: .videoSpeed)
        let after = Set(defaults.dictionaryRepresentation().keys)
        #expect(after.subtracting(before) == ["tools.videoSpeed.options"])
    }
}
