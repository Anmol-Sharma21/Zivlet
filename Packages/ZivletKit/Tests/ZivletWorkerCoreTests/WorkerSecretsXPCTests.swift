import EngineTestSupport
import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit
import ZivletIPC

@testable import ZivletWorkerCore

/// A job's password crosses real XPC inside its own request (plan 20f E3, the prototype's shape: an anonymous listener
/// in this process), reaches the engine as the same bytes, and is wiped in the worker when the step ends.
@Suite("A password crosses real XPC with its job")
struct WorkerSecretsXPCTests {
    @Test func theEngineGetsTheBytesAndTheWorkersCopyIsWipedAfterTheStep() async throws {
        let password = "zv-xpc-" + UUID().uuidString
        let dir = try TempDir(prefix: "zivlet-xpc-secrets")
        let source = try dir.file("Report.pdf", "%PDF-1.7\n")
        let job = JobID()
        let staged = try dir.folder(".zivlet-\(job)").appending(path: "staged.pdf")
        let item = try InputItem(url: source, format: .pdf, byteCount: 9)
        let request = try JobRequest(
            id: job, input: item, operation: .protect(ProtectSpec(mode: .unlock)), destination: dir.url)
        let engine = SecretEngine()
        let client = try RawClient(service: WorkerRig.service([engine]))

        let wire = WireSecrets(JobSecrets(input: JobSecret(utf8: password)))
        let reply = try await client.send(
            Envelope(WorkerRequest.prepare(request, JobWorkspace(job: job, stagedFile: staged), secrets: wire)))

        guard case .planned = reply else {
            Issue.record("not planned: \(reply)")
            return
        }
        #expect(engine.seen == [SecretEngine.Seen(step: "prepare", input: Array(password.utf8), newUser: nil)])
        #expect(engine.secretsGiven.count == 1 && engine.secretsGiven.allSatisfy(\.isWiped))
    }
}
