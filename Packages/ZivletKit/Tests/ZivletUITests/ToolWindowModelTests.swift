import Testing

@testable import ZivletUI

@Suite("The tool window's state (P2-30, plan 20b A1): header, file line and an Apply that says why it is off")
struct ToolWindowModelTests {
    static let lock = ToolWindowModel(
        symbol: "lock.doc", title: "Lock", fileLine: "Report.pdf", apply: .enabled(label: "Lock"))

    @Test(arguments: [
        ([String](), ""),
        (["Report.pdf"], "Report.pdf"),
        (["a.png", "b.pdf", "c.jpg"], "3 files"),
        (["a.png", "b.png"], "2 files"),
    ])
    func theFileLineNamesOneFileOrCountsThem(names: [String], line: String) {
        #expect(ToolWindowModel.fileLine(names: names) == line)
    }

    @Test(arguments: ["", " ", "\n\t "])
    func aDisabledReasonCannotBeEmpty(text: String) {
        #expect(DisabledReason(text) == nil)
    }

    @Test func aDisabledReasonKeepsItsWords() throws {
        let reason = try #require(DisabledReason("Passwords don't match"))
        #expect(reason.text == "Passwords don't match")
    }

    @Test func applySaysWhetherItIsOnAndWhyNot() throws {
        let reason = try #require(DisabledReason("Passwords don't match"))
        let off = ApplyState.disabled(label: "Lock", reason: reason)
        #expect(!off.isEnabled && off.label == "Lock" && off.reason == "Passwords don't match")
        let on = ApplyState.enabled(label: "Lock")
        #expect(on.isEnabled && on.label == "Lock" && on.reason == nil)
    }

    @Test func editsReturnNewValuesAndKeepEveryOtherField() throws {
        let reason = try #require(DisabledReason("Type a password"))
        let off = Self.lock.with(apply: .disabled(label: "Lock", reason: reason))
        #expect(Self.lock.apply.isEnabled)
        #expect(off.apply.reason == "Type a password")
        #expect(off.symbol == Self.lock.symbol && off.title == Self.lock.title && off.fileLine == Self.lock.fileLine)
        let busy = Self.lock.busy()
        #expect(busy.isBusy && !Self.lock.isBusy)
        #expect(busy.with(apply: Self.lock.apply) == busy)
        #expect(busy.busy(false) == Self.lock)
    }

    @Test func aBusyWindowDoesNotApplyAgain() {
        #expect(Self.lock.canApply)
        #expect(!Self.lock.busy().canApply)
    }
}
