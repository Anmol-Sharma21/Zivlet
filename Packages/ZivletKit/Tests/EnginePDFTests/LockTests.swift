import EngineTestSupport
import Foundation
import PDFKit
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EnginePDF

/// A protect job's claimed staging and the engine's three steps, as the worker runs them (plan 20f E4–E6).
struct ProtectRig {
    let dir: TempDir
    let staged: URL
    let job = JobID()

    init(prefix: String = "zivlet-protect") throws {
        dir = try TempDir(prefix: prefix)
        staged = try dir.folder(".zivlet-\(job)").appending(path: "staged.pdf")
        try Data().write(to: staged)
    }

    func request(_ source: URL, _ mode: ProtectSpec.Mode, keep: Bool = false) throws -> JobRequest {
        let item = try InputItem(url: source, format: .pdf, byteCount: PDFEngine.size(of: source))
        return try JobRequest(
            id: job, input: item, operation: .protect(ProtectSpec(mode: mode, keepRestrictions: keep)),
            destination: dir.url)
    }

    /// Prepare, execute and verify with `secrets`; the staged output and the plan's notes after the run.
    func run(_ source: URL, _ mode: ProtectSpec.Mode, _ secrets: JobSecrets, keep: Bool = false) async throws
        -> (output: StagedOutput, notes: [PlanNote])
    {
        let engine = PDFEngine()
        let workspace = JobWorkspace(job: job, stagedFile: staged)
        let plan = try await engine.prepare(
            try request(source, mode, keep: keep), workspace: workspace, secrets: secrets)
        let output = try await engine.execute(plan, context: ExecutionContext(), secrets: secrets)
        try await engine.verify(output, plan: plan, secrets: secrets)
        return (output, plan.notes.filter { !output.withdrawnNotes.contains($0) })
    }

    /// Prepare alone, for refusals.
    func prepare(_ source: URL, _ mode: ProtectSpec.Mode, _ secrets: JobSecrets) async throws(JobError) {
        let request: JobRequest
        do {
            request = try self.request(source, mode)
        } catch {
            throw .internalInvariant("rig request")
        }
        _ = try await PDFEngine().prepare(
            request, workspace: JobWorkspace(job: job, stagedFile: staged), secrets: secrets)
    }
}

/// Every password in these tests is random per run.
func randomPassword(_ prefix: String = "zv") -> String { "\(prefix)-\(UUID().uuidString.prefix(13))" }

/// Lock (P2-106, D-M7-20): AES-256 R6 only; without restrictions the owner password is the user password, with them a
/// separate owner password the app made. Every output is checked by qpdf and PDFKit.
@Suite("Lock writes AES-256 R6 and nothing weaker")
struct LockTests {
    static let restricted = PDFRestrictions(printing: .low, copying: false, editing: false)

    @Test func theEngineTakesProtectJobsAndNoConversion() async {
        let engine = PDFEngine()
        #expect(engine.handles(.protectPDF))
        #expect(await engine.availability(of: .protectPDF) == .available)
        #expect(ConversionCatalog.standard.pairs.allSatisfy { !engine.handles($0) })
    }

    @Test func lockWithoutRestrictionsMakesOnePasswordBothUserAndOwner() async throws {
        let rig = try ProtectRig()
        let password = randomPassword()
        let source = try PDFFixtures.plain(in: rig.dir.url)
        let (output, notes) = try await rig.run(source, .lock(nil), JobSecrets(newUser: JobSecret(utf8: password)))

        #expect(notes.isEmpty)
        let facts = try PDFInspector.inspect(output.url, password: JobSecret(utf8: password))
        #expect(
            facts.encryption == .standard(revision: 6, version: 5, streams: .aes256, strings: .aes256, files: .aes256))
        #expect(facts.matched == .both && facts.pageCount == 2)
        let document = try #require(PDFDocument(url: output.url))
        #expect(document.isLocked)
        #expect(!document.unlock(withPassword: randomPassword("wrong")))
        #expect(document.unlock(withPassword: password) && document.permissionsStatus == .owner)
    }

    @Test func lockWithRestrictionsKeepsTheOwnerPasswordApartAndHoldsTheRestrictions() async throws {
        let rig = try ProtectRig()
        let (user, owner) = (randomPassword("user"), randomPassword("owner"))
        let source = try PDFFixtures.plain(in: rig.dir.url)
        let secrets = JobSecrets(newUser: JobSecret(utf8: user), owner: JobSecret(utf8: owner))
        let (output, _) = try await rig.run(source, .lock(Self.restricted), secrets)

        let byUser = try PDFInspector.inspect(output.url, password: JobSecret(utf8: user))
        #expect(byUser.matched == .user)
        #expect(byUser.permissions.contains(.printLowQuality) && !byUser.permissions.contains(.printHighQuality))
        #expect(!byUser.permissions.contains(.copy) && !byUser.permissions.contains(.modify))
        #expect(byUser.permissions.contains(.accessibility))
        #expect(try PDFInspector.inspect(output.url, password: JobSecret(utf8: owner)).matched == .owner)
        let asUser = try #require(PDFDocument(url: output.url))
        #expect(asUser.unlock(withPassword: user) && asUser.permissionsStatus == .user && !asUser.allowsCopying)
        let asOwner = try #require(PDFDocument(url: output.url))
        #expect(asOwner.unlock(withPassword: owner) && asOwner.permissionsStatus == .owner)
    }

    /// FR-107: a form stays a form; after unlocking with the user password its field still takes a value.
    @Test func aFormKeepsItsFieldsAndTheyStayLive() async throws {
        let rig = try ProtectRig()
        let password = randomPassword()
        let source = try PDFFixtures.form(in: rig.dir.url)
        let (output, _) = try await rig.run(source, .lock(nil), JobSecrets(newUser: JobSecret(utf8: password)))

        let facts = try PDFInspector.inspect(output.url, password: JobSecret(utf8: password))
        #expect(facts.fieldCount == 2 && facts.signatureFieldCount == 1)
        let document = try #require(PDFDocument(url: output.url))
        #expect(document.unlock(withPassword: password))
        let field = try #require(document.page(at: 0)?.annotations.first { $0.fieldName == "fullName" })
        #expect(!field.isReadOnly)
        field.widgetStringValue = "Zivlet"
        #expect(field.widgetStringValue == "Zivlet")
    }

    /// OWN-PDF-1: qpdf opens a file locked with a Devanagari password; PDFKit cannot, so the card gets its note.
    @Test func aDevanagariPasswordLocksAndTheCardSaysPreviewCannotOpenIt() async throws {
        let rig = try ProtectRig()
        let password = "पासवर्ड-" + randomPassword()
        let source = try PDFFixtures.plain(in: rig.dir.url)
        let (output, notes) = try await rig.run(source, .lock(nil), JobSecrets(newUser: JobSecret(utf8: password)))

        #expect(notes == [.passwordNotForPreview])
        #expect(try PDFInspector.inspect(output.url, password: JobSecret(utf8: password)).matched == .both)
        #expect(PDFDocument(url: output.url).map { !$0.unlock(withPassword: password) } == true)
    }

    @Test(arguments: [40, 128])
    func anEncryptedInputIsAlreadyLocked(keyLength: Int) async throws {
        let rig = try ProtectRig()
        let source = try PDFFixtures.encrypted(
            in: rig.dir.url, keyLength: keyLength, user: randomPassword(), owner: randomPassword())
        await #expect(throws: JobError.alreadyEncrypted) {
            try await rig.prepare(source, .lock(nil), JobSecrets(newUser: JobSecret(utf8: randomPassword())))
        }
    }

    @Test func aRestrictionsOnlyInputIsAlreadyLocked() async throws {
        let rig = try ProtectRig()
        let source = try PDFFixtures.restrictionsOnly(in: rig.dir.url, owner: randomPassword())
        await #expect(throws: JobError.alreadyEncrypted) {
            try await rig.prepare(source, .lock(nil), JobSecrets(newUser: JobSecret(utf8: randomPassword())))
        }
    }

    @Test func aLockWithoutItsPasswordsIsABug() async throws {
        let rig = try ProtectRig()
        let source = try PDFFixtures.plain(in: rig.dir.url)
        await #expect(throws: JobError.internalInvariant(PDFEngine.passwordMessage)) {
            try await rig.prepare(source, .lock(nil), JobSecrets())
        }
        await #expect(throws: JobError.internalInvariant(PDFEngine.passwordMessage)) {
            try await rig.prepare(source, .lock(Self.restricted), JobSecrets(newUser: JobSecret(utf8: "abc")))
        }
    }

    @Test(arguments: [
        (PDFRestrictions.none, R6Permissions.all),
        (
            PDFRestrictions(printing: .low, copying: false, editing: false),
            R6Permissions(
                extract: false, assemble: false, annotateAndForm: false, formFilling: false, modifyOther: false,
                printing: .low)
        ),
        (PDFRestrictions(printing: .none, copying: true, editing: true), R6Permissions(printing: .none)),
    ])
    func restrictionsBecomeR6Permissions(restrictions: PDFRestrictions, expected: R6Permissions) {
        #expect(R6Permissions(restrictions) == expected)
    }

    @Test func theRequestOfALockJobGivesTheEngineNoPasswordInThePlan() async throws {
        let rig = try ProtectRig()
        let password = randomPassword()
        let source = try PDFFixtures.plain(in: rig.dir.url)
        let plan = try await PDFEngine().prepare(
            try rig.request(source, .lock(nil)), workspace: JobWorkspace(job: rig.job, stagedFile: rig.staged),
            secrets: JobSecrets(newUser: JobSecret(utf8: password)))
        let json = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
        #expect(!json.contains(password) && !json.lowercased().contains("password"))
    }
}
