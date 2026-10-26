import AppKit
import Testing

@testable import ZivletBox

@Suite("Box keys (17e §2.3, only while the panel is key)")
struct BoxKeyMapTests {
    /// One row per line of 17e §2.3's keyboard table.
    @Test(arguments: [
        (BoxKeyStroke(chars: "a", command: true), BoxCommand.selectAll),
        (BoxKeyStroke(special: .space), .quickLook),
        (BoxKeyStroke(chars: "c", command: true), .copy),
        (BoxKeyStroke(chars: "c", command: true, option: true), .copyPaths),
        (BoxKeyStroke(chars: "m", command: true, shift: true), .moveTo),
        (BoxKeyStroke(chars: "c", command: true, shift: true), .copyTo),
        (BoxKeyStroke(chars: "s", command: true), .share),
        (BoxKeyStroke(special: .delete), .remove),
        (BoxKeyStroke(special: .delete, command: true), .trash),
        (BoxKeyStroke(chars: "n", command: true), .newBox),
        (BoxKeyStroke(chars: "1", command: true), .grid),
        (BoxKeyStroke(chars: "2", command: true), .list),
        (BoxKeyStroke(special: .escape), .collapse),
        (BoxKeyStroke(chars: "w", command: true), .collapse),
        (BoxKeyStroke(special: .left), .move(.left, extend: false)),
        (BoxKeyStroke(special: .right, shift: true), .move(.right, extend: true)),
        (BoxKeyStroke(special: .up), .move(.up, extend: false)),
        (BoxKeyStroke(special: .down), .move(.down, extend: false)),
        (BoxKeyStroke(chars: "p"), .type("p")),
        (BoxKeyStroke(chars: "P", shift: true), .type("P")),
    ])
    func everyRowMaps(_ stroke: BoxKeyStroke, _ command: BoxCommand) {
        #expect(BoxKeyMap.command(for: stroke) == command)
    }

    @Test func otherShortcutsAreLeftToTheSystem() {
        #expect(BoxKeyMap.command(for: BoxKeyStroke(chars: "q", command: true)) == nil)
        #expect(BoxKeyMap.command(for: BoxKeyStroke(chars: "x", control: true)) == nil)
        #expect(BoxKeyMap.command(for: BoxKeyStroke(chars: "")) == nil)
        #expect(BoxKeyMap.command(for: BoxKeyStroke(chars: "\t")) == nil)
    }

    @Test func aStrokeIsReadFromKeyCodesAndCharacters() {
        #expect(BoxKeyStroke(keyCode: 49, chars: " ", flags: []).special == .space)
        #expect(
            BoxKeyStroke(keyCode: 51, chars: "\u{7f}", flags: [.command])
                == BoxKeyStroke(special: .delete, command: true))
        #expect(BoxKeyStroke(keyCode: 53, chars: "\u{1b}", flags: []).special == .escape)
        #expect(BoxKeyStroke(keyCode: 123, chars: "", flags: [.shift]) == BoxKeyStroke(special: .left, shift: true))
        #expect(BoxKeyStroke(keyCode: 124, chars: "", flags: []).special == .right)
        #expect(BoxKeyStroke(keyCode: 125, chars: "", flags: []).special == .down)
        #expect(BoxKeyStroke(keyCode: 126, chars: "", flags: []).special == .up)
        #expect(
            BoxKeyStroke(keyCode: 0, chars: "a", flags: [.option, .control])
                == BoxKeyStroke(chars: "a", option: true, control: true))
    }
}
