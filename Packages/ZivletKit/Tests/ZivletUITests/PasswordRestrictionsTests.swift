import Foundation
import Testing
import ZivletCore

@testable import ZivletUI

/// Lock's restrictions (17a §3.1, D-M7-20): printing, copying and editing; choosing any makes a random owner password,
/// shown once with Copy, which goes with the job as its owner password and is then forgotten.
@Suite("Lock's restrictions and the owner password shown once")
@MainActor
struct PasswordRestrictionsTests {
    let password = "zv-" + UUID().uuidString

    func lockState() -> PasswordSheetState {
        PasswordSheetState(model: PasswordSheetModel(mode: .lock, files: ["Report.pdf"]), announce: { _ in })
    }

    @Test func noRestrictionsMeansNoOwnerPassword() {
        let state = lockState()
        #expect(state.restrictions == .none && state.ownerPassword == nil)
        state.password = password
        state.confirm = password
        let secrets = state.takeSecrets()
        #expect(secrets.owner == nil && state.chosenRestrictions == nil)
    }

    @Test func aRestrictionMakesOneOwnerPasswordThatStays() throws {
        let state = lockState()
        state.setRestrictions(PDFRestrictions(printing: .low, copying: true, editing: true))
        let owner = try #require(state.ownerPassword)
        #expect(owner.count == OwnerPassword.length)
        state.setRestrictions(PDFRestrictions(printing: .low, copying: false, editing: true))
        #expect(state.ownerPassword == owner)
        state.setRestrictions(.none)
        #expect(state.ownerPassword == owner, "turning them back on does not show a second password")
    }

    @Test func theOwnerPasswordGoesWithTheJobAndIsForgotten() throws {
        let state = lockState()
        let restrictions = PDFRestrictions(printing: .none, copying: false, editing: false)
        state.setRestrictions(restrictions)
        let owner = try #require(state.ownerPassword)
        state.password = password
        state.confirm = password
        #expect(state.chosenRestrictions == restrictions)
        let secrets = state.takeSecrets()
        #expect(secrets.owner?.withBytes { Array($0) } == Array(owner.utf8))
        #expect(secrets.newUser?.withBytes { Array($0) } == Array(password.utf8))
        #expect(state.ownerPassword == nil)
    }

    @Test func onlyLockOffersRestrictions() {
        #expect(PasswordSheetModel(mode: .lock, files: ["a.pdf"]).offersRestrictions)
        for mode in [PasswordMode.unlock, .change, .ownerNeeded] {
            #expect(!PasswordSheetModel(mode: mode, files: ["a.pdf"]).offersRestrictions)
        }
    }

    @Test func theRestrictionsCopyIsZivletsOwn() {
        #expect(PasswordCopy.printing == "Printing")
        #expect(PasswordCopy.printingChoices == ["None", "Low quality", "Full"])
        #expect(PasswordCopy.allowCopying == "Allow copying" && PasswordCopy.allowEditing == "Allow editing")
        #expect(PasswordCopy.ownerShownOnce == "Owner password — shown once")
        #expect(PasswordCopy.notSecurity == "Restrictions are honoured by most apps but are not security.")
    }
}
