import Foundation
import Testing
import ZivletCore

@testable import ZivletTrigger

@Suite("Modifier masks and bindings (P0-21, 03a §1.7)")
struct TriggerBindingsTests {
    @Test func defaultsAreShiftCommandControl() {
        let b = TriggerBindings.standard
        #expect(b.mode(matching: .shift) == .convert)
        #expect(b.mode(matching: .command) == .tools)
        #expect(b.mode(matching: .control) == .actions)
        #expect(b.menuSummary == "⇧: Convert · ⌘: Tools · ⌃: Actions")
    }

    @Test func matchIsExact() {
        let b = TriggerBindings.standard
        #expect(b.mode(matching: [.shift, .command]) == nil)
        #expect(b.mode(matching: []) == nil)
        #expect(b.mode(matching: .option) == nil)
    }

    @Test func fifteenNonEmptyCombos() {
        #expect(ModifierMask.allNonEmpty.count == 15)
        #expect(Set(ModifierMask.allNonEmpty).count == 15)
        #expect(ModifierMask(rawValue: 0xFF) == [.control, .option, .shift, .command])
        #expect(ModifierMask([.command, .control, .shift]).symbols == "⌃⇧⌘")
    }

    @Test func emptyAndDuplicateBindingsAreRejected() {
        #expect(throws: BindingError.emptyMask(.tools)) {
            try TriggerBindings(convert: .shift, tools: [], actions: .control)
        }
        #expect(throws: BindingError.duplicate(.shift)) {
            try TriggerBindings(convert: .shift, tools: .shift, actions: .control)
        }
        #expect(throws: BindingError.duplicate(.option)) {
            try TriggerBindings(convert: .shift, tools: .option, actions: .option)
        }
    }

    @Test func encodingCarriesTheSchemaVersionAndRoundTrips() throws {
        let data = try JSONEncoder().encode(TriggerBindings.standard)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Int])
        #expect(object == ["schemaVersion": 1, "convert": 4, "tools": 8, "actions": 1])
        #expect(try JSONDecoder().decode(TriggerBindings.self, from: data) == .standard)
    }

    @Test(arguments: [
        #"{"schemaVersion":1,"convert":0,"tools":0,"actions":255}"#,
        #"{"schemaVersion":1,"convert":4,"tools":4,"actions":1}"#,
        #"{"schemaVersion":1,"convert":4,"tools":8,"actions":8}"#,
        #"{"schemaVersion":2,"convert":4,"tools":8,"actions":1}"#,
        #"{"convert":4,"tools":8,"actions":1}"#,
    ])
    func invalidPayloadsFailToDecode(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TriggerBindings.self, from: Data(json.utf8))
        }
    }

    @Test func chordBindingsWork() throws {
        let b = try TriggerBindings(convert: [.option, .shift], tools: .command, actions: .control)
        #expect(b.mode(matching: [.option, .shift]) == .convert)
        #expect(b.mode(matching: .shift) == nil)
    }
}
