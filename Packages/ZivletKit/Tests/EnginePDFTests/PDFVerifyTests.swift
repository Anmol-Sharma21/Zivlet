import EngineTestSupport
import Foundation
import PDFKit
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EnginePDF

/// P2-105's verify (plan 20e D3, D-M7-23, D-PDF-3): every output passes the shim's check and re-open with what was
/// expected, and a PDFKit re-open. Each expectation passes on a right file and fails on a planted wrong one.
@Suite("Every PDF output is checked twice (D-M7-23)")
struct PDFVerifyTests {
    static let r6Separate = PDFExpectation.locked(revision: 6, method: .aes256, ownerSeparate: true)
    static let r6Same = PDFExpectation.locked(revision: 6, method: .aes256, ownerSeparate: false)

    private func secret(_ text: String) -> JobSecret { JobSecret(utf8: text) }

    /// A two-page AES-256 file written by the shim.
    private func locked(
        in dir: TempDir, user: JobSecret, owner: JobSecret, permissions: R6Permissions = .all, pages: Int = 2
    ) throws -> URL {
        let output = dir.url.appending(path: "locked.pdf")
        let plain = try PDFFixtures.plain(in: dir.url, pages: pages)
        let parameters = R6Parameters(user: user, owner: owner, permissions: permissions)
        try QPDFWriterBridge.write(plain, password: nil, mode: .encryptR6(parameters), to: output)
        return output
    }

    private func expectFailure(_ failure: PDFVerifyFailure, _ body: () throws(PDFEngineError) -> PDFVerifyResult) {
        expectError(.verifyFailed(failure), body)
    }

    private func expectError(_ error: PDFEngineError, _ body: () throws(PDFEngineError) -> PDFVerifyResult) {
        #expect(throws: error) { try body() }
    }

    // MARK: Lock

    @Test func aLockOutputWithItsOwnOwnerPasswordPasses() throws {
        let dir = try TempDir()
        let (user, owner) = (secret("user-pass"), secret("owner-pass"))
        let output = try locked(in: dir, user: user, owner: owner)

        let result = try PDFVerify.verify(
            output, pageCount: 2, expect: [Self.r6Separate], secrets: JobSecrets(newUser: user, owner: owner))

        #expect(result == .passed)
    }

    @Test func aLockOutputWhoseOwnerIsTheUserPasses() throws {
        let dir = try TempDir()
        let same = secret("same-pass")
        let output = try locked(in: dir, user: same, owner: same)

        let result = try PDFVerify.verify(
            output, pageCount: 2, expect: [Self.r6Same], secrets: JobSecrets(newUser: same))

        #expect(result == .passed)
    }

    @Test func anRC4FileIsNotAnR6Output() throws {
        let dir = try TempDir()
        let rc4 = try PDFFixtures.encrypted(in: dir.url, keyLength: 40, user: "u-pass", owner: "o-pass")
        let secrets = JobSecrets(newUser: secret("u-pass"), owner: secret("o-pass"))

        expectFailure(.encryption) { () throws(PDFEngineError) in
            try PDFVerify.verify(rc4, pageCount: 2, expect: [Self.r6Separate], secrets: secrets)
        }
    }

    @Test func aLockOutputWhoseOwnerEqualsTheUserFailsWhereTheyShouldDiffer() throws {
        let dir = try TempDir()
        let same = secret("same-pass")
        let output = try locked(in: dir, user: same, owner: same)

        expectFailure(.ownerPassword) { () throws(PDFEngineError) in
            try PDFVerify.verify(
                output, pageCount: 2, expect: [Self.r6Separate], secrets: JobSecrets(newUser: same, owner: same))
        }
    }

    @Test func aSeparateOwnerFailsWhereTheyShouldBeTheSame() throws {
        let dir = try TempDir()
        let user = secret("user-pass")
        let output = try locked(in: dir, user: user, owner: secret("owner-pass"))

        expectFailure(.ownerPassword) { () throws(PDFEngineError) in
            try PDFVerify.verify(output, pageCount: 2, expect: [Self.r6Same], secrets: JobSecrets(newUser: user))
        }
    }

    @Test func anOwnerPasswordThatDoesNotOpenAsOwnerFails() throws {
        let dir = try TempDir()
        let user = secret("user-pass")
        let output = try locked(in: dir, user: user, owner: secret("owner-pass"))
        let secrets = JobSecrets(newUser: user, owner: secret("some other password"))

        expectFailure(.ownerPassword) { () throws(PDFEngineError) in
            try PDFVerify.verify(output, pageCount: 2, expect: [Self.r6Separate], secrets: secrets)
        }
    }

    @Test func aFileThatOpensWithoutAPasswordIsNotLocked() throws {
        let dir = try TempDir()
        let empty = secret("")
        let output = try locked(in: dir, user: empty, owner: secret("owner-pass"))
        let secrets = JobSecrets(newUser: empty, owner: secret("owner-pass"))

        expectFailure(.opensWithoutItsPassword) { () throws(PDFEngineError) in
            try PDFVerify.verify(output, pageCount: 2, expect: [Self.r6Separate], secrets: secrets)
        }
    }

    @Test func aLockExpectationWithoutItsPasswordIsABug() throws {
        let dir = try TempDir()
        let same = secret("same-pass")
        let output = try locked(in: dir, user: same, owner: same)

        expectError(.internalFailure) { () throws(PDFEngineError) in
            try PDFVerify.verify(output, pageCount: 2, expect: [Self.r6Same], secrets: nil)
        }
        expectError(.internalFailure) { () throws(PDFEngineError) in
            try PDFVerify.verify(
                output, pageCount: 2, expect: [Self.r6Separate], secrets: JobSecrets(newUser: same))
        }
    }

    // MARK: Pages and the check

    @Test func anOutputWithAPageDroppedFails() throws {
        let dir = try TempDir()
        let output = try PDFFixtures.plain(in: dir.url, pages: 1)

        expectFailure(.pageCount) { () throws(PDFEngineError) in
            try PDFVerify.verify(output, pageCount: 2, expect: [])
        }
    }

    @Test func anOutputThatFailsTheCheckFails() throws {
        let dir = try TempDir()
        let noPages = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [] /Count 0 >>"]
        let output = try PDFFixtures.raw(in: dir.url, name: "empty.pdf", objects: noPages)

        expectFailure(.check) { () throws(PDFEngineError) in try PDFVerify.verify(output, pageCount: 0, expect: []) }
    }

    @Test func aLimitInTheCheckStaysALimit() throws {
        let dir = try TempDir()
        let output = try PDFFixtures.plain(in: dir.url)

        expectError(.limit) { () throws(PDFEngineError) in
            try PDFVerify.verify(output, pageCount: 2, expect: [], limits: QPDFLimits(maxPages: 1))
        }
    }

    // MARK: Unlock

    @Test func anUnlockedOutputPasses() throws {
        let dir = try TempDir()
        let output = try PDFFixtures.plain(in: dir.url)

        #expect(try PDFVerify.verify(output, pageCount: 2, expect: [.unlocked]) == .passed)
    }

    @Test func anUnlockedOutputThatIsStillEncryptedFails() throws {
        let dir = try TempDir()
        let same = secret("same-pass")
        let output = try locked(in: dir, user: same, owner: same)

        expectFailure(.encryption) { () throws(PDFEngineError) in
            try PDFVerify.verify(output, pageCount: 2, expect: [.unlocked])
        }
    }

    @Test func anUnlockedOutputThatOpensButStillHasRestrictionsFails() throws {
        let dir = try TempDir()
        let output = try PDFFixtures.restrictionsOnly(in: dir.url, owner: "o-pass")

        expectFailure(.encryption) { () throws(PDFEngineError) in
            try PDFVerify.verify(output, pageCount: 2, expect: [.unlocked])
        }
    }

    // MARK: Preserved

    @Test func anOutputKeepingItsEncryptionPasses() throws {
        let dir = try TempDir()
        let password = secret("u-pass")
        let input = try PDFFixtures.encrypted(in: dir.url, keyLength: 128, user: "u-pass", owner: "o-pass")
        let facts = try PDFInspector.inspect(input, password: password)
        let output = dir.url.appending(path: "kept.pdf")
        try QPDFWriterBridge.write(input, password: password, mode: .preserve, to: output)

        let result = try PDFVerify.verify(
            output, pageCount: 2, expect: [.preserved(from: facts)], secrets: JobSecrets(input: password))

        #expect(result == .passed)
    }

    @Test func aRestrictionsOnlyOutputKeepingItsEncryptionPassesWithoutAPassword() throws {
        let dir = try TempDir()
        let input = try PDFFixtures.restrictionsOnly(in: dir.url, owner: "o-pass")
        let facts = try PDFInspector.inspect(input, password: nil)
        let output = dir.url.appending(path: "kept.pdf")
        try QPDFWriterBridge.write(input, password: nil, mode: .preserve, to: output)

        #expect(try PDFVerify.verify(output, pageCount: 2, expect: [.preserved(from: facts)]) == .passed)
    }

    @Test func anOutputThatChangedItsEncryptionFails() throws {
        let dir = try TempDir()
        let password = secret("u-pass")
        let input = try PDFFixtures.encrypted(
            in: dir.url, name: "aes128.pdf", keyLength: 128, user: "u-pass", owner: "o-pass")
        let facts = try PDFInspector.inspect(input, password: password)
        let output = try locked(in: dir, user: password, owner: secret("o-pass"))

        expectFailure(.encryption) { () throws(PDFEngineError) in
            try PDFVerify.verify(
                output, pageCount: 2, expect: [.preserved(from: facts)], secrets: JobSecrets(input: password))
        }
    }

    @Test func anOutputThatChangedItsPermissionsFails() throws {
        let dir = try TempDir()
        let password = secret("user-pass")
        let output = try locked(
            in: dir, user: password, owner: secret("owner-pass"), permissions: R6Permissions(extract: false))
        let open = try PDFInspector.inspect(output, password: password)
        let before = PDFPreflight(
            pageCount: 2, encryption: open.encryption, permissions: .all, opensWithoutPassword: false, matched: .user)

        expectFailure(.permissions) { () throws(PDFEngineError) in
            try PDFVerify.verify(
                output, pageCount: 2, expect: [.preserved(from: before)], secrets: JobSecrets(input: password))
        }
    }

    // MARK: Forms

    @Test func anOutputThatKeptItsFieldsPasses() throws {
        let dir = try TempDir()
        let output = try PDFFixtures.acroForm(in: dir.url)

        let result = try PDFVerify.verify(
            output, pageCount: 1, expect: [.formsKept(fieldCount: 2, signatureFieldCount: 1)])

        #expect(result == .passed)
    }

    @Test(arguments: [(3, 1), (2, 0)])
    func anOutputThatLostAFieldFails(fields: Int, signatures: Int) throws {
        let dir = try TempDir()
        let output = try PDFFixtures.acroForm(in: dir.url)

        expectFailure(.forms) { () throws(PDFEngineError) in
            try PDFVerify.verify(
                output, pageCount: 1, expect: [.formsKept(fieldCount: fields, signatureFieldCount: signatures)])
        }
    }

    // MARK: PDFKit's side

    @Test func aDevanagariUserPasswordPassesWithANote() throws {
        let dir = try TempDir()
        let user = secret("पासवर्ड-2026")
        let owner = secret("owner-pass")
        let output = try locked(in: dir, user: user, owner: owner)

        let result = try PDFVerify.verify(
            output, pageCount: 2, expect: [Self.r6Separate], secrets: JobSecrets(newUser: user, owner: owner))

        #expect(result == .passedWithNote(.macCannotOpen))
    }

    @Test func aFilePDFKitCannotOpenFails() throws {
        let dir = try TempDir()
        let text = try dir.file("note.pdf", "These words are not a PDF at all.")

        expectFailure(.reader) { () throws(PDFEngineError) in
            try PDFKitReopen.check(text, pageCount: 1, expect: [], user: nil, owner: nil)
        }
    }

    @Test func aFilePDFKitReadsWithOtherPagesFails() throws {
        let dir = try TempDir()
        let output = try PDFFixtures.plain(in: dir.url, pages: 3)

        expectFailure(.pageCount) { () throws(PDFEngineError) in
            try PDFKitReopen.check(output, pageCount: 2, expect: [], user: nil, owner: nil)
        }
    }

    @Test func aFilePDFKitSeesAsPlainIsNotLocked() throws {
        let dir = try TempDir()
        let output = try PDFFixtures.plain(in: dir.url)

        expectFailure(.encryption) { () throws(PDFEngineError) in
            try PDFKitReopen.check(
                output, pageCount: 2, expect: [Self.r6Same], user: self.secret("same-pass"), owner: nil)
        }
    }

    @Test func anEngineVerifyOfAnOutputMissingAPageSaysWhy() async throws {
        let rig = try PDFEngineTests.Rig()
        let plan = try rig.plan(try PDFFixtures.plain(in: rig.dir.url), pageCount: 3)
        let output = try await PDFEngine().execute(plan, context: ExecutionContext())

        await #expect(throws: JobError.verificationFailed(PDFVerifyFailure.pageCount.message)) {
            try await PDFEngine().verify(output, plan: plan)
        }
    }

    @Test func everyFailureHasPlainWordsWithoutAPathOrPassword() {
        let failures: [PDFVerifyFailure] = [
            .check, .pageCount, .encryption, .opensWithoutItsPassword, .ownerPassword, .permissions, .forms, .reader,
        ]

        #expect(Set(failures.map(\.message)).count == failures.count)
        #expect(failures.allSatisfy { !$0.message.contains("/") })
    }

    @Test func anEngineVerifyOfARemovedEncryptionWantsNoEncryptionLeft() async throws {
        let rig = try PDFEngineTests.Rig()
        let input = try PDFFixtures.restrictionsOnly(in: rig.dir.url, owner: "o-pass")
        let plan = try rig.plan(input, encryption: .keep)
        let output = try await PDFEngine().execute(plan, context: ExecutionContext())
        let removal = try rig.plan(input, encryption: .remove)

        await #expect(throws: JobError.verificationFailed(PDFVerifyFailure.encryption.message)) {
            try await PDFEngine().verify(output, plan: removal)
        }
    }
}
