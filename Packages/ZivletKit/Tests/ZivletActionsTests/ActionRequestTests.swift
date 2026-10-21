import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import ZivletActions

@Suite("Action requests: local items only, de-duplicated (C1)")
struct ActionRequestTests {
    let dir: TempDir

    init() throws { dir = try TempDir() }

    @Test func keepsDropOrderAndRemovesDuplicates() throws {
        let a = try dir.file("a.txt")
        let b = try dir.file("b.txt")
        let request = try ActionRequest(
            action: .copyFilePath, urls: [a, b, a, URL(fileURLWithPath: a.path + "/.")], optionHeld: false)
        #expect(request.items == [a.standardizedFileURL, b.standardizedFileURL])
        #expect(request.rejected.isEmpty)
    }

    @Test func remoteAndMissingItemsAreRejectedWithAReason() throws {
        let a = try dir.file("a.txt")
        let remote = try #require(URL(string: "https://example.com/x.png"))
        let request = try ActionRequest(
            action: .copyTo, urls: [a, remote, dir.url.appending(path: "gone.txt")], optionHeld: false)
        #expect(request.items == [a.standardizedFileURL])
        #expect(request.rejected.map(\.reason) == [.notLocal, .missing])
        #expect(request.rejected.map(\.url) == [remote, dir.url.appending(path: "gone.txt")])
    }

    @Test func nothingLocalThrows() throws {
        let remote = try #require(URL(string: "https://example.com"))
        #expect(throws: ActionError.nothingLocal(.shareAirDrop)) {
            try ActionRequest(action: .shareAirDrop, urls: [remote], optionHeld: false)
        }
        #expect(throws: ActionError.nothingLocal(.copyTo)) {
            try ActionRequest(action: .copyTo, urls: [], optionHeld: false)
        }
    }

    @Test func foldersAreAllowedAndTheOptionStateIsKept() throws {
        let sub = try dir.folder("sub")
        let request = try ActionRequest(action: .openInTerminal, urls: [sub], optionHeld: true)
        #expect(request.items == [sub.standardizedFileURL])
        #expect(request.optionHeld && request.action == .openInTerminal)
    }

    @Test func aBrokenSymlinkIsStillALocalItem() throws {
        let link = dir.url.appending(path: "link")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: dir.url.appending(path: "nowhere"))
        #expect(try ActionRequest(action: .moveTo, urls: [link], optionHeld: false).items == [link])
    }

    @Test(arguments: ActionID.allCases)
    func everyActionHasUserCopyForNothingLocal(action: ActionID) {
        let message = ActionError.nothingLocal(action).userMessage
        #expect(!message.isEmpty && message.hasSuffix("."))
    }

    @Test func rejectionReasonsHaveUserCopy() {
        #expect(RejectedItem.Reason.notLocal.userMessage == "Not stored on this Mac.")
        #expect(RejectedItem.Reason.missing.userMessage == "No longer there.")
    }
}
