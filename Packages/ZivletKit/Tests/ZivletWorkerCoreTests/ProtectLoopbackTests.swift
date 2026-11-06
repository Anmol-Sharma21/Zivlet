import EnginePDF
import EngineTestSupport
import Foundation
import PDFKit
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletRuntime

@testable import ZivletWorkerCore

/// The app's scheduler with the real PDF engine in a loopback worker: every request and reply crosses JSON, and the
/// job's passwords travel only in its own requests (plan 20f E4–E7).
struct ProtectWorkerRig {
    let dir: TempDir
    let scheduler: JobScheduler
    let connection: WorkerConnection

    init() async throws {
        dir = try TempDir(prefix: "zivlet-protect-worker")
        let service = WorkerService(engines: [PDFEngine()], pdf: PDFPreflightReader(), onIdle: {})
        connection = WorkerConnection(transport: LoopbackTransport(service: service))
        let capability = try #require(try await connection.capabilities().engine(.pdf))
        scheduler = JobScheduler(
            engines: [RemoteEngine(capability: capability, connection: connection)],
            lanes: .standard(performanceCores: 4), records: nil, processes: SystemProcesses(), clock: { .zero })
    }

    func request(_ source: URL, _ mode: ProtectSpec.Mode, keep: Bool = false) throws -> JobRequest {
        let item = try InputItem(url: source, format: .pdf, byteCount: 1)
        return try JobRequest(
            input: item, operation: .protect(ProtectSpec(mode: mode, keepRestrictions: keep)), destination: dir.url)
    }

    /// Runs the jobs with one shared set of secrets and returns each job's last state, in order.
    func run(_ requests: [JobRequest], _ secrets: JobSecrets) async -> [JobState] {
        let batch = await scheduler.submit(
            requests, secrets: BatchSecrets.shared(secrets, for: requests.map(\.id)))
        var last: [JobID: JobState] = [:]
        for await event in scheduler.events {
            if case .changed(batch, let job, let state) = event { last[job] = state }
            if case .finished(batch) = event { break }
        }
        await scheduler.waitUntilIdle()
        return requests.map { last[$0.id] ?? .queued }
    }
}

extension JobState {
    var publishedURL: URL? {
        guard case .succeeded(let output) = self else { return nil }
        return output.url
    }
}

@Suite("LOCK · UNLOCK through the worker")
struct ProtectLoopbackTests {
    @Test func aLockedReportIsPublishedAsReportLockedAndOpensOnlyWithItsPassword() async throws {
        let rig = try await ProtectWorkerRig()
        let password = "zv-" + UUID().uuidString
        let source = try PDFFixtures.plain(in: rig.dir.url, name: "Report.pdf")
        let secret = JobSecret(utf8: password)

        let states = await rig.run([try rig.request(source, .lock(nil))], JobSecrets(newUser: secret))

        let url = try #require(states.first?.publishedURL, "\(states)")
        #expect(url.lastPathComponent == "Report Locked.pdf")
        let document = try #require(PDFDocument(url: url))
        #expect(document.isLocked && !document.unlock(withPassword: "zv-wrong-" + UUID().uuidString))
        #expect(document.unlock(withPassword: password) && document.permissionsStatus == .owner)
        #expect(secret.isWiped)
        #expect(PDFDocument(url: source)?.isEncrypted == false, "the input is left as it was")
    }

    @Test func theWorkerInspectsADropWithoutAPassword() async throws {
        let rig = try await ProtectWorkerRig()
        let plain = try PDFFixtures.plain(in: rig.dir.url, name: "plain.pdf")
        let locked = try PDFFixtures.encrypted(
            in: rig.dir.url, keyLength: 128, user: "zv-" + UUID().uuidString, owner: "zv-" + UUID().uuidString)
        let damaged = try rig.dir.file("damaged.pdf", "These words are not a PDF.")

        let answers = try await rig.connection.inspectPDFs([plain, locked, damaged])

        guard case .read(let first) = answers[0], case .read(let second) = answers[1] else {
            Issue.record("\(answers)")
            return
        }
        #expect(first.encryption == .none && first.pageCount == 2)
        #expect(second.isShut && second.encryption != .none)
        #expect(answers[2] == .refused(.unsupportedInput(.pdfDamaged)))
    }
}
