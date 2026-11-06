import EngineTestSupport
import Foundation
import PDFKit
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EnginePDF

/// An R6 file the shim writes, in our own words: `user` opens it; `owner` (nil: the same) lifts its restrictions.
func r6File(
    in dir: URL, name: String = "r6.pdf", user: String, owner: String? = nil,
    permissions: R6Permissions = .all
) throws -> URL {
    let source = try PDFFixtures.plain(in: dir, name: "plain-\(name)")
    let output = dir.appending(path: name)
    let ownerSecret = owner.map(JobSecret.init(utf8:))
    let userSecret = JobSecret(utf8: user)
    let parameters = R6Parameters(user: userSecret, owner: ownerSecret ?? userSecret, permissions: permissions)
    try QPDFWriterBridge.write(source, password: nil, mode: .encryptR6(parameters), to: output)
    return output
}

/// Unlock (P2-106, D-M7-21): a decrypted file is written only when the owner password matched or the file grants every
/// permission; restrictions-only files need the owner password; no attempt limit; NFC and NFD are tried silently.
@Suite("Unlock removes a password only when it may")
struct UnlockTests {
    static let restricted = R6Permissions(extract: false, modifyOther: false, printing: .low)

    func expectUnlocked(_ output: StagedOutput, pages: Int = 2) throws {
        let facts = try PDFInspector.inspect(output.url, password: nil)
        #expect(facts.encryption == .none && facts.pageCount == pages)
        #expect(PDFDocument(url: output.url)?.isEncrypted == false)
    }

    @Test func oneR6PasswordThatIsBothUserAndOwnerUnlocks() async throws {
        let rig = try ProtectRig()
        let password = randomPassword()
        let source = try r6File(in: rig.dir.url, user: password)
        let (output, _) = try await rig.run(source, .unlock, JobSecrets(input: JobSecret(utf8: password)))
        try expectUnlocked(output)
    }

    @Test func theUserPasswordOfARestrictedFileAsksForTheOwnersAndWritesNothing() async throws {
        let rig = try ProtectRig()
        let (user, owner) = (randomPassword("user"), randomPassword("owner"))
        let source = try r6File(in: rig.dir.url, user: user, owner: owner, permissions: Self.restricted)
        await #expect(throws: JobError.ownerPasswordNeeded) {
            try await rig.prepare(source, .unlock, JobSecrets(input: JobSecret(utf8: user)))
        }
        #expect(try Data(contentsOf: rig.staged).isEmpty, "nothing written")

        let (output, _) = try await rig.run(source, .unlock, JobSecrets(owner: JobSecret(utf8: owner)))
        try expectUnlocked(output)
    }

    /// The rule's second branch: a file that grants every permission unlocks with its user password.
    @Test func theUserPasswordOfAFileGrantingEverythingUnlocks() async throws {
        let rig = try ProtectRig()
        let (user, owner) = (randomPassword("user"), randomPassword("owner"))
        let source = try r6File(in: rig.dir.url, user: user, owner: owner)
        let (output, _) = try await rig.run(source, .unlock, JobSecrets(input: JobSecret(utf8: user)))
        try expectUnlocked(output)
    }

    @Test func aRestrictionsOnlyFileNeedsItsOwnerPassword() async throws {
        let rig = try ProtectRig()
        let owner = randomPassword("owner")
        let source = try PDFFixtures.restrictionsOnly(in: rig.dir.url, owner: owner)
        await #expect(throws: JobError.ownerPasswordNeeded) { try await rig.prepare(source, .unlock, JobSecrets()) }
        let (output, _) = try await rig.run(source, .unlock, JobSecrets(owner: JobSecret(utf8: owner)))
        try expectUnlocked(output)
    }

    @Test(arguments: [40, 128])
    func legacyRC4AndAES128FilesUnlockWithTheirOwnerPassword(keyLength: Int) async throws {
        let rig = try ProtectRig()
        let owner = randomPassword("owner")
        let source = try PDFFixtures.encrypted(
            in: rig.dir.url, keyLength: keyLength, user: randomPassword("user"), owner: owner)
        let (output, _) = try await rig.run(source, .unlock, JobSecrets(input: JobSecret(utf8: owner)))
        try expectUnlocked(output)
    }

    @Test func anNFDTypedPasswordUnlocksAFileLockedWithNFC() async throws {
        let rig = try ProtectRig()
        let tail = randomPassword()
        let nfc = "caf\u{E9}-2026-" + tail
        let nfd = "cafe\u{301}-2026-" + tail
        #expect(!nfc.unicodeScalars.elementsEqual(nfd.unicodeScalars))
        let source = try r6File(in: rig.dir.url, user: nfc)
        let (output, _) = try await rig.run(source, .unlock, JobSecrets(input: JobSecret(utf8: nfd)))
        try expectUnlocked(output)
    }

    @Test func aCertificateFileIsUnsupported() async throws {
        let rig = try ProtectRig()
        let handler = "<< /Filter /Adobe.PubSec /SubFilter /adbe.pkcs7.s5 /V 4 /R 4 /Length 128 >>"
        let source = try PDFFixtures.raw(
            in: rig.dir.url, name: "certificate.pdf", objects: PDFFixtures.onePageObjects + [handler],
            trailer: "/Encrypt 5 0 R /ID [<00> <00>]")
        await #expect(throws: JobError.unsupportedEncryption) {
            try await rig.prepare(source, .unlock, JobSecrets(input: JobSecret(utf8: randomPassword())))
        }
    }

    /// No attempt counter: ten wrong answers in a row are each just wrong, and the eleventh, right one unlocks.
    @Test func thereIsNoAttemptLimit() async throws {
        let rig = try ProtectRig()
        let password = randomPassword()
        let source = try r6File(in: rig.dir.url, user: password)
        for _ in 1...10 {
            await #expect(throws: JobError.wrongPassword) {
                try await rig.prepare(source, .unlock, JobSecrets(input: JobSecret(utf8: randomPassword("wrong"))))
            }
        }
        let (output, _) = try await rig.run(source, .unlock, JobSecrets(input: JobSecret(utf8: password)))
        try expectUnlocked(output)
    }

    @Test func aFormStaysAFormWhenUnlocked() async throws {
        let rig = try ProtectRig()
        let password = randomPassword()
        let locked = rig.dir.url.appending(path: "form-locked.pdf")
        let user = JobSecret(utf8: password)
        let parameters = R6Parameters(user: user, owner: user)
        try QPDFWriterBridge.write(
            try PDFFixtures.form(in: rig.dir.url), password: nil, mode: .encryptR6(parameters), to: locked)
        let (output, _) = try await rig.run(locked, .unlock, JobSecrets(input: JobSecret(utf8: password)))
        let facts = try PDFInspector.inspect(output.url, password: nil)
        #expect(facts.fieldCount == 2 && facts.signatureFieldCount == 1 && facts.encryption == .none)
    }

    @Test(arguments: [
        (PDFPreflight(pageCount: 1, matched: .owner), true),
        (PDFPreflight(pageCount: 1, matched: .both), true),
        (PDFPreflight(pageCount: 1, permissions: .all, opensWithoutPassword: false, matched: .user), true),
        (PDFPreflight(pageCount: 1, permissions: [.copy], opensWithoutPassword: false, matched: .user), false),
        (PDFPreflight(pageCount: 1, permissions: .all, opensWithoutPassword: true, matched: .user), false),
        (PDFPreflight(pageCount: 1, permissions: [], opensWithoutPassword: true, matched: .user), false),
    ])
    func theRuleIsOnePureFunction(facts: PDFPreflight, mayRemove: Bool) {
        #expect(PDFEngine.mayRemoveEncryption(facts) == mayRemove)
    }
}
