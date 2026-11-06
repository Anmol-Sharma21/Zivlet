import EngineTestSupport
import Foundation
import PDFKit
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EnginePDF

/// Change password (P2-106, D-M7-22): a new user password, written as R6 AES-256 whatever the input had; the owner
/// password and the restrictions stay when the owner password was typed as the current one.
@Suite("Change password writes the new one and keeps what it may")
struct ChangePasswordTests {
    static let r6AES = PDFEncryption.standard(
        revision: 6, version: 5, streams: .aes256, strings: .aes256, files: .aes256)

    func opens(_ url: URL, _ password: String) -> Bool {
        (try? PDFInspector.inspect(url, password: JobSecret(utf8: password))) != nil
    }

    @Test func theOldPasswordNoLongerOpensTheOutputAndTheNewOneDoes() async throws {
        let rig = try ProtectRig()
        let (old, new) = (randomPassword("old"), randomPassword("new"))
        let source = try r6File(in: rig.dir.url, user: old)
        let secrets = JobSecrets(input: JobSecret(utf8: old), newUser: JobSecret(utf8: new))
        let (output, _) = try await rig.run(source, .changePassword, secrets)

        #expect(!opens(output.url, old))
        let facts = try PDFInspector.inspect(output.url, password: JobSecret(utf8: new))
        #expect(facts.encryption == Self.r6AES && facts.matched == .both)
        #expect(PDFDocument(url: output.url).map { $0.unlock(withPassword: new) } == true)
    }

    @Test func theOwnerPasswordAndTheRestrictionsSurviveWhenTheOwnerPasswordWasTyped() async throws {
        let rig = try ProtectRig()
        let (user, owner, new) = (randomPassword("user"), randomPassword("owner"), randomPassword("new"))
        let restricted = R6Permissions(extract: false, modifyOther: false, printing: .low)
        let source = try r6File(in: rig.dir.url, user: user, owner: owner, permissions: restricted)
        let before = try PDFInspector.inspect(source, password: JobSecret(utf8: user)).permissions
        let secrets = JobSecrets(input: JobSecret(utf8: owner), newUser: JobSecret(utf8: new))
        let (output, _) = try await rig.run(source, .changePassword, secrets, keep: true)

        #expect(!opens(output.url, user))
        let byNew = try PDFInspector.inspect(output.url, password: JobSecret(utf8: new))
        #expect(byNew.matched == .user && byNew.permissions == before)
        #expect(try PDFInspector.inspect(output.url, password: JobSecret(utf8: owner)).matched == .owner)
    }

    @Test func aRestrictedFileNeedsItsOwnerPasswordToChange() async throws {
        let rig = try ProtectRig()
        let (user, owner) = (randomPassword("user"), randomPassword("owner"))
        let source = try r6File(
            in: rig.dir.url, user: user, owner: owner, permissions: R6Permissions(extract: false))
        await #expect(throws: JobError.ownerPasswordNeeded) {
            try await rig.prepare(
                source, .changePassword,
                JobSecrets(input: JobSecret(utf8: user), newUser: JobSecret(utf8: randomPassword("new"))))
        }
    }

    @Test(arguments: [40, 128])
    func aLegacyInputIsUpgradedToR6(keyLength: Int) async throws {
        let rig = try ProtectRig()
        let (user, owner, new) = (randomPassword("user"), randomPassword("owner"), randomPassword("new"))
        let source = try PDFFixtures.encrypted(in: rig.dir.url, keyLength: keyLength, user: user, owner: owner)
        let secrets = JobSecrets(input: JobSecret(utf8: owner), newUser: JobSecret(utf8: new))
        let (output, _) = try await rig.run(source, .changePassword, secrets)

        let facts = try PDFInspector.inspect(output.url, password: JobSecret(utf8: new))
        #expect(facts.encryption == Self.r6AES)
        #expect(!opens(output.url, user))
    }

    @Test func aWrongCurrentPasswordIsWrong() async throws {
        let rig = try ProtectRig()
        let source = try r6File(in: rig.dir.url, user: randomPassword())
        await #expect(throws: JobError.wrongPassword) {
            try await rig.prepare(
                source, .changePassword,
                JobSecrets(input: JobSecret(utf8: randomPassword("wrong")), newUser: JobSecret(utf8: "zv-new")))
        }
    }

    @Test(arguments: [
        PDFPermissions.all, [.printLowQuality, .accessibility], [.printLowQuality, .printHighQuality, .copy],
        [],
    ])
    func permissionsReadBackAsR6Permissions(bits: PDFPermissions) {
        #expect(R6Permissions(bits).pdfPermissions == bits)
    }
}
