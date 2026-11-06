import EngineVision
import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import ZivletIPC

/// A job's passwords travel with its own requests only (plan 20f E3, D-M7-14): each request of a protect job, and a
/// text or code job's request for a locked PDF, carries them; nothing else may. On the wire they are bytes inside
/// `WireSecrets`, shown as `<password>` everywhere.
@Suite("A job's passwords travel with its own requests only")
struct WireSecretsTests {
    let password = "zv-wire-" + UUID().uuidString
    let owner = "zv-owner-" + UUID().uuidString

    func secrets() -> JobSecrets {
        JobSecrets(input: JobSecret(utf8: password), newUser: JobSecret(utf8: password), owner: JobSecret(utf8: owner))
    }

    static func protectRequest(_ rig: ValidatorRig, source: URL) throws -> JobRequest {
        let item = try InputItem(url: source, format: .pdf, byteCount: 4)
        return try JobRequest(
            id: rig.job, input: item, operation: .protect(ProtectSpec(mode: .unlock)), destination: rig.dir.url)
    }

    static func pdfPlan(_ rig: ValidatorRig, source: URL) throws -> ExecutionPlan {
        try ExecutionPlan(
            engine: .pdf, stages: [.pdf(PDFStage(source: source, encryption: .remove, pageCount: 1))],
            stageWeights: [1], lanes: [.cpu], outputFormat: .pdf, stagedFile: rig.staged)
    }

    /// Every request kind that may carry a job's passwords, with them.
    func carriers(_ rig: ValidatorRig, wire: WireSecrets?) throws -> [WorkerRequest] {
        let source = try rig.dir.file("locked.pdf", "%PDF-1.7\n")
        let plan = try Self.pdfPlan(rig, source: source)
        let output = StagedOutput(format: .pdf, url: rig.staged, byteCount: 9)
        return [
            .prepare(
                try Self.protectRequest(rig, source: source), JobWorkspace(job: rig.job, stagedFile: rig.staged),
                secrets: wire),
            .execute(rig.job, plan, outputByteLimit: nil, secrets: wire), .verify(output, plan, secrets: wire),
            .recognizeText(TextJob(inputs: [source], languages: [.english]), secrets: wire),
            .readCodes(CodeJob(inputs: [source]), secrets: wire),
        ]
    }

    @Test func eachCarrierRoundTripsWithTheSameBytes() throws {
        let rig = try ValidatorRig()
        let wire = WireSecrets(secrets())
        for request in try carriers(rig, wire: wire) {
            let decoded = try Envelope<WorkerRequest>.decode(Envelope(request).encoded()).body
            #expect(decoded == request)
            #expect(decoded.secrets?.secrets().input?.withBytes { Array($0) } == Array(password.utf8))
            #expect(decoded.secrets?.secrets().owner?.withBytes { Array($0) } == Array(owner.utf8))
        }
    }

    @Test func noDescriptionOfACarrierShowsAPassword() throws {
        let rig = try ValidatorRig()
        for request in try carriers(rig, wire: WireSecrets(secrets())) {
            var dumped = ""
            dump(request, to: &dumped)
            let texts = [dumped, String(describing: request), String(reflecting: request)]
            #expect(texts.allSatisfy { !$0.contains(password) && !$0.contains(owner) })
            #expect(dumped.contains(JobSecret.redacted))
        }
    }

    @Test func noSecretsMeansNoWireForm() {
        #expect(WireSecrets(nil) == nil)
        #expect(WireSecrets(JobSecrets()) == nil)
        #expect(WireSecrets(JobSecrets(input: JobSecret(utf8: "x")))?.count == 1)
    }

    @Test func theRequestsOfEveryOtherJobHaveNoSecrets() {
        #expect(IPCFixtures.requests.allSatisfy { $0.secrets == nil })
    }

    @Test func theCarriersPassTheValidator() throws {
        let rig = try ValidatorRig()
        let validator = WorkerRequestValidator(hostedEngines: [.pdf, .vision])
        for request in try carriers(rig, wire: WireSecrets(secrets())) { try validator.validate(request) }
    }

    @Test(arguments: [1, 127])
    func aPasswordOfOneTo127BytesPasses(bytes: Int) throws {
        let rig = try ValidatorRig()
        let validator = WorkerRequestValidator(hostedEngines: [.pdf])
        let wire = WireSecrets(JobSecrets(input: JobSecret(utf8: String(repeating: "k", count: bytes))))
        let source = try rig.dir.file("locked.pdf", "%PDF-1.7\n")
        try validator.validate(
            .execute(rig.job, try Self.pdfPlan(rig, source: source), outputByteLimit: nil, secrets: wire))
    }

    @Test(arguments: [0, 128])
    func aPasswordOutsideOneTo127BytesIsRefused(bytes: Int) throws {
        let rig = try ValidatorRig()
        let validator = WorkerRequestValidator(hostedEngines: [.pdf])
        let wire = try #require(
            WireSecrets(entries: [.init(.input, JobSecret(utf8: String(repeating: "k", count: bytes)))]))
        let source = try rig.dir.file("locked.pdf", "%PDF-1.7\n")
        #expect(throws: JobError.unsupportedInput(.badPassword)) {
            try validator.validate(
                .execute(rig.job, try Self.pdfPlan(rig, source: source), outputByteLimit: nil, secrets: wire))
        }
    }

    @Test func fourSecretsOrARoleTwiceAreRefused() throws {
        let rig = try ValidatorRig()
        let validator = WorkerRequestValidator(hostedEngines: [.pdf])
        let source = try rig.dir.file("locked.pdf", "%PDF-1.7\n")
        let plan = try Self.pdfPlan(rig, source: source)
        let roles: [WireSecrets.Role] = [.input, .newUser, .owner, .owner]
        let four = try #require(WireSecrets(entries: roles.map { .init($0, JobSecret(utf8: "abc")) }))
        let twice = try #require(
            WireSecrets(entries: [.init(.input, JobSecret(utf8: "a")), .init(.input, JobSecret(utf8: "b"))]))
        for wire in [four, twice] {
            #expect(throws: JobError.unsupportedInput(.badPassword)) {
                try validator.validate(.execute(rig.job, plan, outputByteLimit: nil, secrets: wire))
            }
        }
    }

    @Test func secretsOnAConversionOrAnImagePlanOrAPictureForTextAreRefused() throws {
        let rig = try ValidatorRig()
        let wire = try #require(WireSecrets(secrets()))
        guard case .prepare(let conversion, let workspace, _) = try rig.prepare() else {
            Issue.record("not a prepare")
            return
        }
        let misplaced: [WorkerRequest] = [
            .prepare(conversion, workspace, secrets: wire),
            .execute(rig.job, try rig.plan(), outputByteLimit: nil, secrets: wire),
            .verify(StagedOutput(format: .jpg, url: rig.staged, byteCount: 3), try rig.plan(), secrets: wire),
            .recognizeText(TextJob(inputs: [rig.input], languages: [.english]), secrets: wire),
            .readCodes(CodeJob(inputs: [rig.input]), secrets: wire),
        ]
        for request in misplaced {
            #expect(rig.refusal(request) == WorkerRequestValidator.misplacedSecrets, "\(request)")
        }
    }

    @Test func aPDFInspectionNeedsSafeRegularFilesAndNoMoreThanItsLimit() throws {
        let rig = try ValidatorRig()
        let validator = WorkerRequestValidator(hostedEngines: [.pdf])
        let pdf = try rig.dir.file("plain.pdf", "%PDF-1.7\n")
        try validator.validate(.inspectPDFs([pdf]))
        #expect(throws: JobError.unsupportedInput(.notAFile)) {
            try validator.validate(.inspectPDFs([rig.dir.url.appending(path: "hosts.png")]))
        }
        let many = Array(repeating: pdf, count: WorkerRequestValidator.maximumInspections + 1)
        #expect(throws: WorkerRequestValidator.tooManyInspections) { try validator.validate(.inspectPDFs(many)) }
        #expect(throws: JobError.engineMissing(.pdf)) {
            try WorkerRequestValidator(hostedEngines: [.image]).validate(.inspectPDFs([pdf]))
        }
    }
}
