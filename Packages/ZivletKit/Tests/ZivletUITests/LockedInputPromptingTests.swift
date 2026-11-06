import Foundation
import Testing
import ZivletCore

@testable import ZivletUI

/// A locked PDF in Copy Text or Read QR (P2-107, plan 20f E10): one Unlock sheet per locked file; a password that does
/// not open it shakes the sheet (the second sheet), the right one gives the file's result; Cancel skips the file.
@Suite("Locked inputs ask once per file")
@MainActor
struct LockedInputPromptingTests {
    let file = URL(fileURLWithPath: "/in/Menu.pdf")

    func secrets(_ text: String) -> PasswordAnswer {
        .secrets(JobSecrets(input: JobSecret(utf8: text)), sameForAll: false)
    }

    @Test func theRightPasswordGivesTheFilesResult() async {
        let prompter = ProtectBatchTests.FakePrompter([secrets("right")])
        let result = await LockedInputPrompting.unlock(file, prompter: prompter, near: nil) { secrets in
            secrets.input?.withBytes { String(decoding: $0, as: UTF8.self) } == "right" ? "the text" : nil
        }
        #expect(result == "the text")
        #expect(prompter.asked.map(\.mode) == [.unlock] && prompter.asked.first?.files == ["Menu.pdf"])
    }

    @Test func aWrongPasswordAsksAgainInTheSecondSheet() async {
        let prompter = ProtectBatchTests.FakePrompter([secrets("wrong"), secrets("right")])
        let result = await LockedInputPrompting.unlock(file, prompter: prompter, near: nil) { secrets in
            secrets.input?.withBytes { String(decoding: $0, as: UTF8.self) } == "right" ? 7 : nil
        }
        #expect(result == 7)
        #expect(prompter.retried == [["Menu.pdf"]])
    }

    @Test func cancelSkipsTheFile() async {
        let prompter = ProtectBatchTests.FakePrompter([.cancelled])
        var attempts = 0
        let result: String? = await LockedInputPrompting.unlock(file, prompter: prompter, near: nil) { _ in
            attempts += 1
            return "never"
        }
        #expect(result == nil && attempts == 0)
    }

    @Test func twoLockedFilesAreAskedOneEach() async {
        let prompter = ProtectBatchTests.FakePrompter([secrets("a"), secrets("b")])
        let files = [URL(fileURLWithPath: "/in/a.pdf"), URL(fileURLWithPath: "/in/b.pdf")]
        let results = await LockedInputPrompting.unlockEach(files, prompter: prompter, near: nil) { file, secrets in
            secrets.input?.withBytes { String(decoding: $0, as: UTF8.self) }
                == file.deletingPathExtension().lastPathComponent
                ? file.lastPathComponent : nil
        }
        #expect(prompter.asked.map(\.files) == [["a.pdf"], ["b.pdf"]])
        #expect(results == [files[0]: "a.pdf", files[1]: "b.pdf"])
    }
}
